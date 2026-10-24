"""Add commute schedules, occurrences, inbox and worker state; no existing tables changed."""
from alembic import op
from app.departure.models import Schedule, Occurrence, NotificationEvent, Installation, DeviceToken, WorkerState

revision = '002'
down_revision = '001'


def upgrade():
    for model in (Schedule, Occurrence, NotificationEvent, Installation, DeviceToken, WorkerState):
        model.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    # Explicit Alembic downgrade is destructive to commute data; never run automatically.
    for model in (WorkerState, DeviceToken, Installation, NotificationEvent, Occurrence, Schedule):
        model.__table__.drop(op.get_bind())
