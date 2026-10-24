from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import AliasChoices, Field
from typing import Literal


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', extra='ignore')
    tomtom_api_key: str = ''
    search_provider: Literal['tomtom', 'geoapify'] = 'geoapify'
    geoapify_api_key: str = ''
    geoapify_daily_budget: int = Field(default=1000, ge=1, le=3000)
    geoapify_daily_credits: int = Field(default=2000, ge=1, le=3000)
    geoapify_budget_file: str = '.geoapify-budget.db'
    app_access_token: str = ''
    database_url: str = 'postgresql+psycopg://trafficgo:trafficgo@localhost:5432/trafficgo'
    cors_origins: list[str] = []
    daily_provider_budget: int = 2000
    api_requests_per_minute: int = Field(default=180, ge=1)
    tile_requests_per_minute: int = Field(default=600, ge=1)
    provider_budget_file: str = '.provider-budget.json'
    routing_provider: Literal['tomtom', 'valhalla'] = 'valhalla'
    valhalla_base_url: str = Field(default='', validation_alias=AliasChoices('VALHALLA_URL', 'VALHALLA_BASE_URL', 'valhalla_base_url'))
    routing_fallback_to_tomtom: bool = False
    interactive_routing_budget_file: str = '.routing-budget.db'
    interactive_daily_routing_limit: int = Field(default=96, ge=1, le=200)
    departure_live_routing_enabled: bool = False
    departure_daily_routing_limit: int = Field(default=24, ge=1, le=100)
    jwt_secret: str = ''
    jwt_issuer: str = 'trafficgo'
    jwt_audience: str = 'trafficgo'


settings = Settings()
