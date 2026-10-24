"""Database inbox is real; push transport is explicitly unconfigured by default."""
from typing import Protocol
from sqlalchemy import select
from .models import NotificationEvent, DeviceToken

MESSAGES = {
    'preparation_soon': 'Sắp đến giờ chuẩn bị',
    'preparation_due': 'Đến giờ chuẩn bị',
    'departure_soon': 'Còn ít phút đến giờ xuất phát',
    'departure_due': 'Đến giờ xuất phát',
    'eta_increased': 'ETA tăng đáng kể',
    'leave_earlier': 'Nên xuất phát sớm hơn',
    'late_risk': 'Có nguy cơ đi muộn',
}


class PushNotificationProvider(Protocol):
    async def send(self, token: str, payload: dict, idempotency_key: str) -> str:
        """Return delivered, invalid_token, or retry. Adapter must use idempotency_key."""
        ...


class NotificationService:
    def emit(self, session, schedule, occurrence, kind, now):
        message = MESSAGES.get(kind, 'Nhắc lại giờ xuất phát')
        schedule_revision = occurrence.data.get('revision', 1)
        if schedule_revision > 1:
            kind = f'{kind}:s{schedule_revision}'
        revision = occurrence.data.get('exception_revision', 0)
        if revision:
            kind = f'{kind}:{revision}'
        # Unique DB constraint is the final protection across restart/repeated ticks.
        found = session.scalar(select(NotificationEvent).where(
            NotificationEvent.occurrence_id == occurrence.id, NotificationEvent.kind == kind))
        if found:
            return found
        row = NotificationEvent(user_id=schedule.user_id, occurrence_id=occurrence.id,
            kind=kind, created_at=now.isoformat(), data={
                'title': message, 'schedule_name': schedule.data['name'],
                'schedule_id': schedule.id, 'route': {k: schedule.data.get(k) for k in
                    ('origin', 'destination', 'origin_name', 'destination_name', 'vehicle', 'journey_id', 'direction')},
                'arrival_date': occurrence.arrival_date,
                'arrival_at': occurrence.data.get('arrival_at'),
                'departure_at': occurrence.data.get('departure_at'),
                'eta_s': occurrence.data.get('eta_s'),
                'eta_source': occurrence.data.get('eta_source'),
                'eta_updated_at': occurrence.data.get('eta_updated_at'),
                'traffic_aware': occurrence.data.get('traffic_aware', False)},
            delivery_status='inbox_only')
        session.add(row)
        session.flush()
        return row


async def deliver_push(session, event, provider: PushNotificationProvider):
    """Future worker hook. Not called without a configured, tested adapter.

    Providers must deduplicate event.id + device.id. This is an outbox hook,
    not a claim of exactly-once remote delivery after a crash.
    """
    results = []
    for device in session.scalars(select(DeviceToken).where(
            DeviceToken.user_id == event.user_id, DeviceToken.active.is_(True))):
        result = await provider.send(device.data['token'], event.data, f'{event.id}:{device.id}')
        if result == 'invalid_token':
            device.active = False
        results.append(result)
    event.delivery_status = ('delivered' if results and all(r == 'delivered' for r in results)
                             else 'pending' if results else 'no_device')
