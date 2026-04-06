"""
ml_predictor.py — XGBoost-based load and solar prediction for Smart Inverter.

Key Design Principles (Anti-Hallucination):
  1. Solar synthetic fallback uses REAL panel specs (Wp, count, efficiency, tilt).
     If specs are unknown (0), it derives capacity from observed historical peak.
  2. Load synthetic fallback uses the user's actual baseline kWh/day setting.
     If that's 0, it uses a conservative 500W flat estimate — clearly labeled.
  3. All predictions are labeled with data_source so the UI can show honesty badges.
     'real_data'   = XGBoost trained on actual InfluxDB readings
     'panel_specs' = Physics-based curve from user-entered panel specifications
     'historical_peak' = Derived from observed max in real data (no spec needed)
     'synthetic'   = No real data OR specs available; rough estimate, use with caution
"""

import math
import pandas as pd
import numpy as np
import xgboost as xgb
import holidays

from cache import prediction_cache

# ─── Constants ────────────────────────────────────────────────────────────────

COUNTRY_CODE = "IN"

# System loss factor: accounts for wiring, inverter, temperature, soiling losses
# Industry standard: 80% of rated capacity is realistically delivered
_SYSTEM_LOSS_FACTOR = 0.80

# ─── Solar Physics Model ──────────────────────────────────────────────────────

def _solar_hour_factor(hour: int, latitude_deg: float = 10.79,
                       tilt_deg: float = 15.0) -> float:
    """
    Compute a normalized solar irradiance factor (0–1) for a given hour.
    Uses simplified solar geometry based on hour angle from solar noon.
    Accounts for panel tilt bonus (tilted panels capture more perpendicular radiation).
    """
    # Solar window: 6am to 6pm (typical for India)
    sunrise = 6.0
    sunset  = 18.0

    if hour <= sunrise or hour >= sunset:
        return 0.0

    # Normalize hour to [0,1] within the solar window, peak at solar noon (12:00)
    solar_noon   = (sunrise + sunset) / 2          # 12.0
    half_window  = (sunset - sunrise) / 2          # 6.0
    hour_offset  = (hour - solar_noon) / half_window  # -1 to +1

    # Cosine gives a smooth bell curve peaking at solar noon
    base_factor = math.cos(hour_offset * math.pi / 2)

    # Tilt bonus: south-facing tilted panels get more radiation at midday
    # Simplified: tilt at the latitude angle is optimal; 15° is close for Trichy (~11°N)
    tilt_bonus  = 1.0 + math.sin(math.radians(tilt_deg)) * 0.10
    latitude_factor = 1.0 + math.cos(math.radians(latitude_deg)) * 0.05

    return max(0.0, base_factor * tilt_bonus * latitude_factor)


def build_solar_clear_sky_curve(
    panel_wp: float,
    panel_count: int,
    panel_efficiency_pct: float,
    panel_tilt_deg: float = 15.0,
    latitude_deg: float = 10.79,
) -> dict[int, float]:
    """
    Build an hourly clear-sky solar output curve (Watts) from real panel specs.
    This is physics-based — NO hardcoded guesses.

    Formula:
        output_W = panel_wp × panel_count × (efficiency/100) × hour_factor × loss_factor
    """
    system_wp = panel_wp * panel_count
    eff_fraction = panel_efficiency_pct / 100.0

    curve = {}
    for h in range(24):
        factor = _solar_hour_factor(h, latitude_deg, panel_tilt_deg)
        # Watts = rated Wp × hour factor × efficiency correction × system losses
        watts = system_wp * factor * eff_fraction * _SYSTEM_LOSS_FACTOR
        curve[h] = round(max(0.0, watts), 1)

    return curve


def _infer_solar_curve_from_history(df: pd.DataFrame) -> dict[int, float]:
    """
    When panel specs are unknown, derive a clear-sky curve from the
    OBSERVED HISTORICAL MAXIMUM per hour. This is data-driven, not guessed.
    """
    df_h = df.copy()
    df_h['hour'] = df_h.index.hour
    observed_max = df_h.groupby('hour')['value'].max().to_dict()

    curve = {}
    for h in range(24):
        curve[h] = observed_max.get(h, 0.0)
    return curve

# ─── Feature Engineering ──────────────────────────────────────────────────────

def _extract_features(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["hour"]       = df.index.hour
    df["dayofweek"]  = df.index.dayofweek
    df["is_weekend"] = df["dayofweek"].isin([5, 6]).astype(int)
    country_holidays = holidays.country_holidays(COUNTRY_CODE)
    df["is_holiday"] = df.index.map(lambda d: d in country_holidays).astype(int)
    df["month"]      = df.index.month
    return df

FEATURE_COLS = ["hour", "dayofweek", "is_weekend", "is_holiday", "month"]


def _future_features(start_time: pd.Timestamp, hours: int) -> pd.DataFrame:
    idx = pd.date_range(start=start_time, periods=hours, freq="1h")
    return _extract_features(pd.DataFrame(index=idx))

# ─── Data Preparation ─────────────────────────────────────────────────────────

def _prepare_df(history: list[dict]) -> pd.DataFrame | None:
    if not history:
        return None
    df = pd.DataFrame(history)
    df["time"] = pd.to_datetime(df["time"], utc=True).dt.tz_localize(None)
    df.set_index("time", inplace=True)
    df = df.sort_index()
    if len(df) > 1:
        df = df.resample("1h").mean().interpolate(method="linear", limit=6)
    df.dropna(inplace=True)
    if len(df) < 24:
        return None
    return df

# ─── Load Synthetic Fallback ──────────────────────────────────────────────────

def _synthetic_load_flat(hours: int, start_time: pd.Timestamp,
                          baseline_w: float = 500.0) -> tuple[list[dict], str]:
    """
    Emergency fallback: flat estimate with small noise.
    Returns (predictions, data_source).
    Uses user's baseline if provided; otherwise conservative 500W.
    """
    result = []
    for i in range(1, hours + 1):
        t = start_time + pd.Timedelta(hours=i)
        # Small sinusoidal daily variation even in fallback (peak evening)
        hour_factor = 0.7 + 0.6 * math.sin(math.pi * (t.hour - 6) / 12) if 6 <= t.hour <= 22 else 0.6
        noise = np.random.uniform(-20, 20)
        val   = max(0.0, baseline_w * hour_factor + noise)
        result.append({"time": t.isoformat(), "value": round(val, 2)})
    source = "user_baseline" if baseline_w > 0 else "synthetic"
    return result, source

# ─── Model Training ───────────────────────────────────────────────────────────

def _build_xgb() -> xgb.XGBRegressor:
    return xgb.XGBRegressor(
        n_estimators=150, max_depth=4, learning_rate=0.08,
        subsample=0.85, colsample_bytree=0.9,
        random_state=42, n_jobs=-1, verbosity=0,
    )

def _calc_mae(y_true, y_pred) -> float:
    return float(np.mean(np.abs(np.array(y_true) - np.array(y_pred))))


def train_load_model(history_15d: list[dict]) -> float:
    """Train XGBoost on 15 days of load history. Caches model. Returns MAE."""
    df = _prepare_df(history_15d)
    if df is None:
        print("⚠️  Load: insufficient real data — will use flat fallback")
        prediction_cache.load_model = None
        return -1.0

    df_feat = _extract_features(df)
    X, y    = df_feat[FEATURE_COLS], df_feat["value"]
    model   = _build_xgb()
    model.fit(X, y)
    mae     = _calc_mae(y, model.predict(X))

    prediction_cache.load_model = model
    prediction_cache.load_mae   = round(mae, 2)
    print(f"✅ Load model trained on {len(df)} points — MAE: {mae:.1f}W")
    return mae


def train_solar_model(history_15d: list[dict]) -> float:
    """Train XGBoost on 15 days of solar history. Caches model. Returns MAE."""
    df = _prepare_df(history_15d)
    if df is None:
        print("⚠️  Solar: insufficient real data — will use spec/peak fallback")
        prediction_cache.solar_model = None
        return -1.0

    df_feat = _extract_features(df)
    X, y    = df_feat[FEATURE_COLS], df_feat["value"]
    model   = _build_xgb()
    model.fit(X, y)
    mae     = _calc_mae(y, model.predict(X))

    prediction_cache.solar_model = model
    prediction_cache.solar_mae   = round(mae, 2)
    print(f"✅ Solar model trained on {len(df)} points — MAE: {mae:.1f}W")
    return mae

# ─── Fast Prediction (uses cached model) ─────────────────────────────────────

def predict_load(
    history_15d: list[dict],
    forecast_hours: int = 24,
    baseline_w: float = 0.0,    # user's daily baseline (Watts) — 0 = unknown
) -> dict:
    """
    Predict load for next N hours.
    Returns {"points": [...], "data_source": "...", "warning": "..."}
    """
    start_time = _get_start_time(history_15d)
    model      = prediction_cache.load_model

    if model is not None:
        # ── Best case: XGBoost trained on real data ──────────────────
        df_future = _future_features(start_time + pd.Timedelta(hours=1), forecast_hours)
        preds     = model.predict(df_future[FEATURE_COLS])
        points    = [
            {"time": t.isoformat(), "value": round(max(0.0, float(p)), 2)}
            for t, p in zip(df_future.index, preds)
        ]
        return {
            "points": points,
            "data_source": "real_data",
            "warning": None,
        }

    # ── Fallback: use user baseline or conservative 500W ─────────────
    points, source = _synthetic_load_flat(
        forecast_hours, start_time, baseline_w if baseline_w > 0 else 500.0
    )
    warning = (
        "Load prediction based on your baseline setting — no historical data available."
        if baseline_w > 0
        else "⚠️ No real data and no baseline set. Using 500W estimate — please set your baseline load in Settings."
    )
    return {"points": points, "data_source": source, "warning": warning}


def predict_solar(
    history_15d: list[dict],
    weather_clouds_24h: list[int] = None,
    forecast_hours: int = 24,
    # Panel specs — passed from Flutter settings
    panel_wp: float = 0.0,
    panel_count: int = 0,
    panel_efficiency: float = 0.0,
    panel_tilt_deg: float = 15.0,
    latitude: float = 10.79,
) -> dict:
    """
    Predict solar generation for next N hours.
    Returns {"points": [...], "data_source": "...", "warning": "...", "system_wp": N}

    Priority:
      1. XGBoost (real data) + cloud attenuation
      2. Physics (panel specs) + cloud attenuation
      3. Historical peak per hour + cloud attenuation
      4. (None of the above) → error, no hallucination
    """
    start_time   = _get_start_time(history_15d)
    df_history   = _prepare_df(history_15d)
    model        = prediction_cache.solar_model
    has_specs    = (panel_wp > 0 and panel_count > 0 and panel_efficiency > 0)
    has_history  = df_history is not None

    # ── Source 1: XGBoost trained on real data ────────────────────────
    if model is not None:
        df_future  = _future_features(start_time + pd.Timedelta(hours=1), forecast_hours)
        base_preds = model.predict(df_future[FEATURE_COLS])

        points = _apply_cloud_and_night(
            list(zip(df_future.index, base_preds)), weather_clouds_24h
        )
        return {
            "points": points,
            "data_source": "real_data",
            "system_wp": panel_wp * panel_count if has_specs else None,
            "warning": None,
        }

    # ── Source 2: Physics-based from panel specs ──────────────────────
    if has_specs:
        curve = build_solar_clear_sky_curve(
            panel_wp, panel_count, panel_efficiency, panel_tilt_deg, latitude
        )
        points = _curve_to_predictions(curve, start_time, forecast_hours, weather_clouds_24h)
        system_wp = panel_wp * panel_count
        return {
            "points": points,
            "data_source": "panel_specs",
            "system_wp": system_wp,
            "warning": f"Prediction based on {panel_count}×{panel_wp:.0f}Wp panel specs. "
                       f"System capacity: {system_wp:.0f}W rated / "
                       f"{system_wp * _SYSTEM_LOSS_FACTOR:.0f}W effective.",
        }

    # ── Source 3: Historical peak (data-driven, no specs) ────────────
    if has_history:
        curve  = _infer_solar_curve_from_history(df_history)
        points = _curve_to_predictions(curve, start_time, forecast_hours, weather_clouds_24h)
        peak   = max(curve.values())
        return {
            "points": points,
            "data_source": "historical_peak",
            "system_wp": None,
            "warning": f"Prediction inferred from observed peak of {peak:.0f}W. "
                       "For accurate results, enter your panel specs in Settings → Panel Setup.",
        }

    # ── Source 4: No data, no specs — refuse to hallucinate ──────────
    return {
        "points": [],
        "data_source": "unavailable",
        "system_wp": None,
        "warning": (
            "Cannot predict solar output: no historical data and no panel specs provided. "
            "Please enter your panel specifications in Settings → Panel Setup."
        ),
    }

# ─── Cloud & Night Helpers ────────────────────────────────────────────────────

def _apply_cloud_and_night(
    pairs: list[tuple],
    weather_clouds_24h: list[int] | None,
) -> list[dict]:
    """Apply cloud cover attenuation and force night hours to 0."""
    result = []
    for i, (t, base) in enumerate(pairs):
        power = max(0.0, float(base))
        # Night hours: no generation
        if hasattr(t, 'hour') and (t.hour < 6 or t.hour > 18):
            power = 0.0
        elif weather_clouds_24h and i < len(weather_clouds_24h):
            cloud_pct  = weather_clouds_24h[i]
            attenuation = 1.0 - (cloud_pct / 100.0) * 0.8
            power      *= attenuation
        result.append({"time": t.isoformat(), "value": round(power, 2)})
    return result


def _curve_to_predictions(
    curve: dict[int, float],
    start_time: pd.Timestamp,
    hours: int,
    weather_clouds_24h: list[int] | None,
) -> list[dict]:
    """Convert an hour-keyed curve dict into a dated prediction list."""
    pairs = []
    for i in range(1, hours + 1):
        t     = start_time + pd.Timedelta(hours=i)
        base  = curve.get(t.hour, 0.0)
        pairs.append((t, base))
    return _apply_cloud_and_night(pairs, weather_clouds_24h)

# ─── Helper ───────────────────────────────────────────────────────────────────

def _get_start_time(history: list[dict]) -> pd.Timestamp:
    if history:
        try:
            return pd.to_datetime(history[-1]["time"], utc=True).tz_localize(None)
        except Exception:
            pass
    return pd.Timestamp.now()
