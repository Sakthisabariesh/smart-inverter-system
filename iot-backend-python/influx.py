from influxdb_client import InfluxDBClient, Point, WriteOptions
from influxdb_client.client.write_api import SYNCHRONOUS

from settings import settings

_client = InfluxDBClient(
    url=settings.influx_url,
    token=settings.influx_token,
    org=settings.influx_org,
)

_query_api = _client.query_api()
_write_api = _client.write_api(write_options=SYNCHRONOUS)


# ---------------------------------------------------------------------------
# Keep-alive  (ping InfluxDB Serverless so the free instance stays awake)
# ---------------------------------------------------------------------------

def keep_influx_alive() -> None:
    point = Point("keep_alive").field("ping", 1.0)
    _write_api.write(bucket=settings.influx_bucket, record=point)
    print("InfluxDB keep-alive ping sent")


# ---------------------------------------------------------------------------
# Latest reading  →  GET /power
# ---------------------------------------------------------------------------

def get_power_data() -> dict:
    """Return a flat dict of the latest values for every field in inverter_data."""

    flux = f"""
from(bucket: "{settings.influx_bucket}")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "inverter_data")
  |> last()
"""
    tables = _query_api.query(flux)
    data: dict = {}
    for table in tables:
        for record in table.records:
            data[record.get_field()] = record.get_value()
    return data


# ---------------------------------------------------------------------------
# Historical time-series  →  GET /history
# ---------------------------------------------------------------------------

ALLOWED_FIELDS = {"pv_input_w", "load_w", "battery_percent", "temperature", "battery_voltage"}
ALLOWED_RANGES = {"1h", "6h", "24h"}

_WINDOW_MAP = {"1h": "15s", "6h": "2m", "24h": "10m"}


def get_history_data(field: str, range_: str) -> list[dict]:
    """Return a list of {time, value} dicts for the requested field + range."""

    every = _WINDOW_MAP.get(range_, "1m")

    flux = f"""
from(bucket: "{settings.influx_bucket}")
  |> range(start: -{range_})
  |> filter(fn: (r) => r._measurement == "inverter_data")
  |> filter(fn: (r) => r._field == "{field}")
  |> aggregateWindow(every: {every}, fn: mean, createEmpty: false)
  |> sort(columns: ["_time"])
"""
    tables = _query_api.query(flux)
    points: list[dict] = []
    for table in tables:
        for record in table.records:
            raw = record.get_value()
            points.append(
                {
                    "time": record.get_time().isoformat(),
                    "value": round(float(raw), 2) if raw is not None else 0.0,
                }
            )
    return points
