from uuid import uuid4
from sqlalchemy import String, JSON, ForeignKey, UniqueConstraint, Integer, Float
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


def uid():
    return str(uuid4())


class Schedule(Base):
    __tablename__ = 'commute_schedules'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    data: Mapped[dict] = mapped_column(JSON)
    revision: Mapped[int] = mapped_column(Integer, default=1)


class Occurrence(Base):
    __tablename__ = 'commute_occurrences'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    schedule_id: Mapped[str] = mapped_column(ForeignKey('commute_schedules.id', ondelete='CASCADE'), index=True)
    arrival_date: Mapped[str] = mapped_column(String(10))
    status: Mapped[str] = mapped_column(String(20), default='planned')
    data: Mapped[dict] = mapped_column(JSON)
    __table_args__ = (UniqueConstraint('schedule_id', 'arrival_date'),)


class NotificationEvent(Base):
    __tablename__ = 'notification_events'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    occurrence_id: Mapped[str] = mapped_column(ForeignKey('commute_occurrences.id', ondelete='CASCADE'), index=True)
    kind: Mapped[str] = mapped_column(String(32))
    created_at: Mapped[str] = mapped_column(String(40))
    read: Mapped[bool] = mapped_column(default=False)
    data: Mapped[dict] = mapped_column(JSON)
    delivery_status: Mapped[str] = mapped_column(String(32), default='inbox_only')
    __table_args__ = (UniqueConstraint('occurrence_id', 'kind'),)


class Installation(Base):
    __tablename__ = 'commute_installations'
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)


class DeviceToken(Base):
    __tablename__ = 'push_device_tokens'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    data: Mapped[dict] = mapped_column(JSON)
    active: Mapped[bool] = mapped_column(default=True)


class WorkerState(Base):
    __tablename__ = 'departure_worker_state'
    name: Mapped[str] = mapped_column(String(64), primary_key=True)
    owner: Mapped[str] = mapped_column(String(36), default='')
    lease_until: Mapped[float] = mapped_column(Float, default=0)
    data: Mapped[dict] = mapped_column(JSON, default=dict)
