from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    influx_url: str
    influx_token: str
    influx_org: str
    influx_bucket: str
    port: int = 8000


settings = Settings()
