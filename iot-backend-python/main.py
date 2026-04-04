from contextlib import asynccontextmanager
import asyncio

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from influx import (
    get_power_data,
    get_history_data,
    keep_influx_alive,
    ALLOWED_FIELDS,
    ALLOWED_RANGES,
)


# ---------------------------------------------------------------------------
# Lifespan — keep-alive task starts when the server starts
# ---------------------------------------------------------------------------

async def _keep_alive_loop() -> None:
    """Fire a keep-alive ping every 10 minutes (matches original Node.js behaviour)."""
    while True:
        try:
            keep_influx_alive()
        except Exception as exc:
            print(f"Keep-alive error: {exc}")
        await asyncio.sleep(10 * 60)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # startup
    task = asyncio.create_task(_keep_alive_loop())
    yield
    # shutdown
    task.cancel()


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Smart Inverter API",
    description="IoT backend for the Smart Inverter Flutter app.",
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/", tags=["health"])
def root():
    return {"message": "Smart Energy Backend Running"}


@app.get("/power", tags=["inverter"])
async def power():
    """
    Return the latest inverter reading.

    Fields: battery_percent, battery_voltage, pv_input_w, load_w, temperature
    Plus normalised aliases expected by the Flutter client:
      battery, voltage, power, current, solar_w, load_w
    """
    try:
        data = await asyncio.to_thread(get_power_data)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    battery_pct = data.get("battery_percent", 0) or 0
    battery_v   = data.get("battery_voltage", 0)  or 0
    pv_w        = data.get("pv_input_w", 0)        or 0
    load_w      = data.get("load_w", 0)            or 0
    temperature = data.get("temperature", 0)        or 0

    current = round(pv_w / battery_v, 2) if pv_w and battery_v else 0.0

    return {
        **data,
        # normalised aliases
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
):
    """
    Return aggregated time-series for a single field.

    - **field**: pv_input_w | load_w | battery_percent | temperature | battery_voltage
    - **range**: 1h | 6h | 24h
    """
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
        points = await asyncio.to_thread(get_history_data, field, range)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {"field": field, "range": range, "points": points}
