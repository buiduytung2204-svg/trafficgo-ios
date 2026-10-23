from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import AliasChoices, Field
from typing import Literal


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', extra='ignore')
    tomtom_api_key: str = ''
    app_access_token: str = ''
    database_url: str = 'postgresql+psycopg://trafficgo:trafficgo@localhost:5432/trafficgo'
    cors_origins: list[str] = []
    daily_provider_budget: int = 2000
    api_requests_per_minute: int = Field(default=180, ge=1)
    tile_requests_per_minute: int = Field(default=600, ge=1)
    provider_budget_file: str = '.provider-budget.json'
    routing_provider: Literal['tomtom', 'valhalla'] = 'tomtom'
    valhalla_base_url: str = Field(default='', validation_alias=AliasChoices('VALHALLA_URL', 'VALHALLA_BASE_URL', 'valhalla_base_url'))
    routing_fallback_to_tomtom: bool = False
    jwt_secret: str = ''
    jwt_issuer: str = 'trafficgo'
    jwt_audience: str = 'trafficgo'


settings = Settings()
