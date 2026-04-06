from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    # ── InfluxDB ──────────────────────────────────────────────────────
    influx_url: str
    influx_token: str
    influx_org: str
    influx_bucket: str

    # ── External APIs ─────────────────────────────────────────────────
    weather_api_key: str = ""
    port: int = 8000

    # ── Default Solar Panel Specs (overridable per-request from Flutter) ──
    # These are SERVER-SIDE defaults only. The Flutter app sends real values.
    # Set to 0 deliberately — prediction will use data-driven peak if 0.
    default_panel_wp: float = 0.0        # Rated power per panel (Watts)
    default_panel_count: int = 0         # Number of panels
    default_panel_efficiency: float = 0.0 # Panel efficiency %
    default_panel_tilt_deg: float = 15.0  # Tilt from horizontal (degrees)
    default_latitude: float = 10.79      # Location latitude (Trichy default)
    default_longitude: float = 78.70     # Location longitude


settings = Settings()
