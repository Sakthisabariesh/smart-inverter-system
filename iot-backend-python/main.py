from contextlib import asynccontextmanager
import asyncio
import time
import traceback

import httpx
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from influx import (
    get_power_data,
    get_history_data,
    keep_influx_alive,
    ALLOWED_FIELDS,
    ALLOWED_RANGES,
)
from settings import settings
import ml_predictor
from cache import prediction_cache

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def log_error(exc):
    with open("error_log.txt", "a") as f:
        f.write(traceback.format_exc() + "\n")


async def _fetch_weather_clouds(city: str, hours: int) -> list[int]:
    """Fetch hourly cloud cover % from OpenWeatherMap 3-hour forecast API."""
    api_key = settings.weather_api_key
    if not api_key:
        return []
    url = f"https://api.openweathermap.org/data/2.5/forecast?q={city}&appid={api_key}"
    try:
        async with httpx.AsyncClient(timeout=6) as client:
            resp = await client.get(url)
            if resp.status_code == 200:
                raw = resp.json().get("list", [])
                clouds: list[int] = []
                for item in raw[: hours // 3 + 1]:
                    c = item["clouds"]["all"]
                    clouds.extend([c, c, c])   # expand 3h → 3 × 1h
                return clouds[:hours]
    except Exception as exc:
        log_error(exc)
    return []


# ---------------------------------------------------------------------------
# Background: model training + cache refresh
# ---------------------------------------------------------------------------

REFRESH_INTERVAL_SECONDS = 30 * 60   # 30 minutes


async def _refresh_prediction_cache() -> None:
    """Fetch 15-day data, train both models, cache predictions."""
    print("🔄 Refreshing prediction cache...")
    t0 = time.monotonic()

    # ── Load model ──────────────────────────────────────────────────
    try:
        load_history = await asyncio.to_thread(get_history_data, "load_w", "15d")
    except Exception as exc:
        log_error(exc)
        load_history = []
        print(f"⚠️  InfluxDB load fetch failed: {exc}")

    await asyncio.to_thread(ml_predictor.train_load_model, load_history)

    # Cache 24-hour predictions
    load_result = await asyncio.to_thread(ml_predictor.predict_load, load_history, 24)
    prediction_cache.load_predictions = load_result["points"]

    # ── Solar model ─────────────────────────────────────────────────
    try:
        solar_history = await asyncio.to_thread(get_history_data, "pv_input_w", "15d")
    except Exception as exc:
        log_error(exc)
        solar_history = []
        print(f"⚠️  InfluxDB solar fetch failed: {exc}")

    await asyncio.to_thread(ml_predictor.train_solar_model, solar_history)

    # Cache solar predictions (no weather for background job — use historical means)
    # Panel specs come from server-side settings (user can override per-request)
    solar_result = await asyncio.to_thread(
        ml_predictor.predict_solar,
        solar_history, [], 24,
        settings.default_panel_wp,
        settings.default_panel_count,
        settings.default_panel_efficiency,
        settings.default_panel_tilt_deg,
        settings.default_latitude,
    )
    prediction_cache.solar_predictions = solar_result["points"]
    prediction_cache.solar_data_source = solar_result.get("data_source", "unknown")
    prediction_cache.solar_warning     = solar_result.get("warning")

    # ── Mark cache ready ─────────────────────────────────────────────
    prediction_cache.training_data_points = len(load_history)
    prediction_cache.last_refreshed_at    = time.time()
    prediction_cache.is_ready             = True

    elapsed = time.monotonic() - t0
    print(f"✅ Prediction cache ready ({elapsed:.1f}s). "
          f"Data points: {len(load_history)} load / {len(solar_history)} solar")


async def _prediction_refresh_loop() -> None:
    """Background loop: refresh models every REFRESH_INTERVAL_SECONDS."""
    # First run immediately on startup
    try:
        await _refresh_prediction_cache()
    except Exception as exc:
        log_error(exc)
        print(f"❌ Initial model training failed: {exc}")

    while True:
        await asyncio.sleep(REFRESH_INTERVAL_SECONDS)
        try:
            await _refresh_prediction_cache()
        except Exception as exc:
            log_error(exc)
            print(f"❌ Cache refresh failed: {exc}")


async def _keep_alive_loop() -> None:
    """Fire a keep-alive ping every 10 minutes."""
    while True:
        try:
            keep_influx_alive()
        except Exception as exc:
            log_error(exc)
            print(f"Keep-alive error: {exc}")
        await asyncio.sleep(10 * 60)


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    tasks = [
        asyncio.create_task(_prediction_refresh_loop()),
        asyncio.create_task(_keep_alive_loop()),
    ]
    yield
    for t in tasks:
        t.cancel()


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Smart Inverter API",
    description="IoT backend for the Smart Inverter Flutter app.",
    version="3.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Routes — Health
# ---------------------------------------------------------------------------

@app.get("/", tags=["health"])
def root():
    return {"message": "Smart Energy Backend Running", "version": "3.0.0"}


# ---------------------------------------------------------------------------
# Routes — Inverter Data
# ---------------------------------------------------------------------------

@app.get("/power", tags=["inverter"])
async def power():
    """Return the latest inverter reading."""
    try:
        data = await asyncio.to_thread(get_power_data)
    except Exception as exc:
        log_error(exc)
        raise HTTPException(status_code=500, detail=str(exc))

    battery_pct = data.get("battery_percent", 0) or 0
    battery_v   = data.get("battery_voltage", 0)  or 0
    pv_w        = data.get("pv_input_w", 0)        or 0
    load_w      = data.get("load_w", 0)            or 0
    temperature = data.get("temperature", 0)        or 0

    current = round(pv_w / battery_v, 2) if pv_w and battery_v else 0.0

    return {
        **data,
        "battery":     battery_pct,
        "voltage":     battery_v,
        "power":       pv_w,
        "current":     current,
        "solar_w":     pv_w,
        "load_w":      load_w,
        "temperature": temperature,
    }


@app.get("/history", tags=["inverter"])
async def history(
    field: str = Query(default="pv_input_w"),
    range: str = Query(default="1h"),
    daily: bool = Query(default=False),
):
    """Return aggregated time-series for a single field."""
    if field not in ALLOWED_FIELDS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid field. Allowed: {', '.join(sorted(ALLOWED_FIELDS))}",
        )
    if range not in ALLOWED_RANGES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid range. Allowed: {', '.join(sorted(ALLOWED_RANGES))}",
        )
    try:
        every_ = "1d" if daily else None
        points = await asyncio.to_thread(get_history_data, field, range, every_)
    except Exception as exc:
        log_error(exc)
        raise HTTPException(status_code=500, detail=str(exc))

    return {"field": field, "range": range, "points": points}


# ---------------------------------------------------------------------------
# Routes — Weather
# ---------------------------------------------------------------------------

@app.get("/weather", tags=["weather"])
async def get_weather(city: str = Query(default="Trichy")):
    """Return a smart summary of the current weather for the provided city."""
    api_key = settings.weather_api_key
    if not api_key:
        return {"insight": "Weather API Missing"}

    url = f"https://api.openweathermap.org/data/2.5/weather?q={city}&appid={api_key}&units=metric"
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            resp = await client.get(url)
            if resp.status_code == 200:
                data = resp.json()
                temp = data.get("main", {}).get("temp", 0)
                desc = data.get("weather", [{}])[0].get("main", "Clear")

                insight = "Clear"
                if "Rain" in desc or "Drizzle" in desc:
                    insight = "🌧️ Rainy soon"
                elif "Cloud" in desc:
                    insight = "☁️ Dull / Cloudy"
                elif temp > 35:
                    insight = "🔥 Very Hot"
                elif "Clear" in desc:
                    insight = "☀️ Sunny"

                return {"temp": temp, "condition": desc, "insight": insight, "city": city}
    except Exception as exc:
        log_error(exc)

    return {"insight": "Weather Unavailable"}


# ---------------------------------------------------------------------------
# Routes — AI Prediction  (fast: serve from cache)
# ---------------------------------------------------------------------------

@app.get("/predict/load", tags=["prediction"])
async def predict_load_endpoint(
    hours: int = Query(default=24, le=48),
    baseline_w: float = Query(default=0.0, description="User's daily baseline load in Watts. 0 = use real data only."),
):
    """
    Predict future load power (XGBoost, trained on last 15 days).
    Served from in-memory cache — responds in < 200ms.
    Pass baseline_w from Flutter UserSettings.baselineLoad * 1000 / 24
    for a fallback when real data is sparse.
    """
    if prediction_cache.is_ready and hours == 24 and prediction_cache.load_predictions:
        return {
            "field": "load_w",
            "points": prediction_cache.load_predictions,
            "data_source": "real_data",
            "warning": None,
            "cached": True,
            "cache_age": prediction_cache.age_label(),
        }

    try:
        history = await asyncio.to_thread(get_history_data, "load_w", "15d")
    except Exception as exc:
        log_error(exc)
        history = []

    try:
        result = await asyncio.to_thread(ml_predictor.predict_load, history, hours, baseline_w)
    except Exception as exc:
        log_error(exc)
        raise HTTPException(status_code=500, detail=f"Prediction Error: {exc}")

    return {
        "field": "load_w",
        "points": result["points"],
        "data_source": result["data_source"],
        "warning": result["warning"],
        "cached": False,
        "cache_age": prediction_cache.age_label(),
    }


@app.get("/predict/solar", tags=["prediction"])
async def predict_solar_endpoint(
    hours: int = Query(default=24, le=48),
    city: str = Query(default="Trichy"),
    # Panel specs sent from Flutter UserSettings — 0 means not configured
    panel_wp: float = Query(default=0.0, description="Rated power per panel in Watts"),
    panel_count: int = Query(default=0, description="Number of solar panels"),
    panel_efficiency: float = Query(default=0.0, description="Panel efficiency in %"),
    panel_tilt_deg: float = Query(default=15.0, description="Panel tilt angle in degrees"),
    latitude: float = Query(default=10.79, description="Location latitude"),
):
    """
    Predict future solar generation.
    Accepts real panel specifications from Flutter settings — no hallucination.
    data_source field tells the UI how the prediction was made:
      'real_data'       → XGBoost trained on 15d of real inverter readings
      'panel_specs'     → Physics-based from your entered panel specifications
      'historical_peak' → Derived from observed historical max (no specs needed)
      'unavailable'     → Cannot predict without data or specs
    """
    weather_clouds = await _fetch_weather_clouds(city, hours)

    # Use request panel specs, fall back to server defaults
    eff_panel_wp    = panel_wp    or settings.default_panel_wp
    eff_panel_count = panel_count or settings.default_panel_count
    eff_efficiency  = panel_efficiency or settings.default_panel_efficiency
    eff_tilt        = panel_tilt_deg or settings.default_panel_tilt_deg
    eff_lat         = latitude or settings.default_latitude

    # Cache hit: re-apply weather attenuation on top of cached values
    if prediction_cache.is_ready and hours == 24 and prediction_cache.solar_predictions:
        base_pts = prediction_cache.solar_predictions
        if weather_clouds:
            adjusted = []
            for i, pt in enumerate(base_pts):
                power = pt["value"]
                if i < len(weather_clouds):
                    power *= (1.0 - (weather_clouds[i] / 100.0) * 0.8)
                adjusted.append({"time": pt["time"], "value": round(max(0.0, power), 2)})
            base_pts = adjusted

        return {
            "field": "pv_input_w",
            "points": base_pts,
            "data_source": getattr(prediction_cache, "solar_data_source", "real_data"),
            "warning": getattr(prediction_cache, "solar_warning", None),
            "system_wp": eff_panel_wp * eff_panel_count if eff_panel_wp > 0 else None,
            "cached": True,
            "cache_age": prediction_cache.age_label(),
        }

    # Cache miss → compute with real panel specs
    try:
        history = await asyncio.to_thread(get_history_data, "pv_input_w", "15d")
    except Exception as exc:
        log_error(exc)
        history = []

    try:
        result = await asyncio.to_thread(
            ml_predictor.predict_solar,
            history, weather_clouds, hours,
            eff_panel_wp, eff_panel_count, eff_efficiency, eff_tilt, eff_lat,
        )
    except Exception as exc:
        log_error(exc)
        raise HTTPException(status_code=500, detail=f"Prediction Error: {exc}")

    return {
        "field": "pv_input_w",
        "points": result["points"],
        "data_source": result["data_source"],
        "warning": result["warning"],
        "system_wp": result.get("system_wp"),
        "cached": False,
        "cache_age": prediction_cache.age_label(),
    }


@app.get("/predict/status", tags=["prediction"])
async def predict_status():
    """
    Returns the health and accuracy of the prediction models.
    Great for competition demo — shows the AI is live and accurate.
    """
    return {
        "is_ready":             prediction_cache.is_ready,
        "last_refreshed":       prediction_cache.age_label(),
        "training_data_points": prediction_cache.training_data_points,
        "load_model": {
            "trained":  prediction_cache.load_model is not None,
            "mae_watts": prediction_cache.load_mae,
        },
        "solar_model": {
            "trained":  prediction_cache.solar_model is not None,
            "mae_watts": prediction_cache.solar_mae,
        },
        "refresh_interval_min": REFRESH_INTERVAL_SECONDS // 60,
    }
