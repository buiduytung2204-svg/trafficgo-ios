from datetime import datetime, timezone
from typing import Literal
from pydantic import BaseModel, Field, field_validator


class Coordinate(BaseModel):
    lat: float = Field(ge=20.5, le=21.6)
    lon: float = Field(ge=105.2, le=106.3)


class RouteRequest(BaseModel):
    origin: Coordinate
    destination: Coordinate
    vehicle: Literal['car', 'motorcycle'] = 'car'
    departure: datetime | None = None
    avoid_tolls: bool = False
    avoid_highways: bool = False

    @field_validator('departure')
    @classmethod
    def future_departure(cls, value):
        if value and (value.tzinfo is None or value < datetime.now(timezone.utc)):
            raise ValueError('Departure must be timezone-aware and in the future')
        return value


class Route(BaseModel):
    id: str
    distance_m: int = Field(ge=0)
    duration_s: int = Field(ge=0)
    traffic_delay_s: int | None = Field(default=None, ge=0)
    geometry: list[Coordinate] = Field(min_length=2)
    legs: list[dict]
    instructions: list[dict] = []
    provider: str = 'tomtom'
    retrieved_at: datetime
    vehicle: str
    traffic_aware: bool = True
    fallback_reason: str | None = None


class SavedPlace(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    coordinate: Coordinate
    category: Literal['home', 'school', 'work', 'favorite'] = 'favorite'


class UserSettings(BaseModel):
    vehicle: Literal['car', 'motorcycle'] = 'car'
    traffic: bool = True
    theme: Literal['system', 'light', 'dark'] = 'system'
    search_history: bool = False
