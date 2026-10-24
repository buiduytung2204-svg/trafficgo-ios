from datetime import date, time
from typing import Literal
from pydantic import BaseModel, Field, model_validator
from app.schemas import Coordinate


class ScheduleInput(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    # User-owned route reference plus endpoints, not provider route geometry.
    saved_route_id: str | None = Field(default=None, max_length=36)
    journey_id: str | None = Field(default=None, max_length=100)
    direction: Literal['outbound', 'inbound'] | None = None
    route_name: str = Field(default='', max_length=100)
    origin: Coordinate
    destination: Coordinate
    origin_name: str = Field(default='', max_length=100)
    destination_name: str = Field(default='', max_length=100)
    vehicle: Literal['car', 'motorcycle'] = 'car'
    arrival_time: str = Field(pattern=r'^([01]\d|2[0-3]):[0-5]\d$')
    weekdays: list[int] = Field(default_factory=lambda: [0, 1, 2, 3, 4], max_length=7)
    one_off_date: date | None = None
    preparation_minutes: int = Field(default=15, ge=0, le=180)
    buffer_minutes: int = Field(default=10, ge=0, le=180)
    enabled: bool = True
    initial_eta_s: int | None = Field(default=None, ge=60, le=14400)

    @model_validator(mode='after')
    def recurrence(self):
        if any(d < 0 or d > 6 for d in self.weekdays) or len(set(self.weekdays)) != len(self.weekdays):
            raise ValueError('Weekdays must be unique Monday=0..Sunday=6')
        if not self.one_off_date and not self.weekdays:
            raise ValueError('Choose weekdays or one_off_date')
        time.fromisoformat(self.arrival_time)
        return self


class OccurrenceAction(BaseModel):
    status: Literal['skipped', 'completed', 'cancelled']


class DeviceInput(BaseModel):
    token: str = Field(min_length=16, max_length=4096)
    platform: Literal['android', 'ios']
