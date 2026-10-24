from datetime import datetime, timezone
from uuid import uuid4
from sqlalchemy import ForeignKey, String, JSON, DateTime, Index
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy import create_engine, event


def database_engine(url):
    engine = create_engine(url, pool_pre_ping=True)
    if engine.dialect.name == 'sqlite':
        @event.listens_for(engine, 'connect')
        def sqlite_constraints(connection, _):
            cursor = connection.cursor()
            cursor.execute('PRAGMA foreign_keys=ON')
            cursor.execute('PRAGMA busy_timeout=5000')
            cursor.close()
    return engine


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = 'users'
    id: Mapped[str] = mapped_column(String(128), primary_key=True)


class SavedPlaceRow(Base):
    __tablename__ = 'saved_places'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    data: Mapped[dict] = mapped_column(JSON)


class SavedRouteRow(Base):
    __tablename__ = 'saved_routes'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    # Only user-entered endpoints/preferences, never provider geometry by default.
    data: Mapped[dict] = mapped_column(JSON)


class RouteCheck(Base):
    __tablename__ = 'route_checks'
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    checked_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    # Opt-in aggregate diagnostics only. No continuous location log.
    status: Mapped[str] = mapped_column(String(32))
    __table_args__ = (Index('ix_checks_time', 'checked_at'),)


class SettingsRow(Base):
    __tablename__ = 'user_settings'
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), primary_key=True)
    data: Mapped[dict] = mapped_column(JSON)
