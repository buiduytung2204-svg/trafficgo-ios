"""Clock-injected pure policy. No HTTP, threads, global clock, or provider calls."""
from datetime import datetime, timedelta, time, date
from zoneinfo import ZoneInfo

ZONE = ZoneInfo('Asia/Ho_Chi_Minh')
TERMINAL = {'completed', 'skipped', 'cancelled', 'missed'}


def local(now):
    if now.tzinfo is None:
        raise ValueError('Clock must be timezone-aware')
    return now.astimezone(ZONE)


def moments(arrival, eta_s, preparation_minutes, buffer_minutes):
    departure = arrival - timedelta(seconds=eta_s, minutes=buffer_minutes)
    return departure - timedelta(minutes=preparation_minutes), departure


def candidate_arrivals(data, now):
    now = local(now)
    if data.get('one_off_date'):
        day = date.fromisoformat(data['one_off_date'])
        yield datetime.combine(day, time.fromisoformat(data['arrival_time']), ZONE)
        return
    # Includes yesterday for restart catch-up and a full week for the next commute.
    for offset in range(-1, 8):
        day = now.date() + timedelta(days=offset)
        matches = (day.isoformat() == data['one_off_date'] if data.get('one_off_date')
                   else day.weekday() in data['weekdays'])
        if matches:
            yield datetime.combine(day, time.fromisoformat(data['arrival_time']), ZONE)


def interval_seconds(departure, now):
    remaining = (departure - local(now)).total_seconds()
    # Public demo: at most 4 refreshes/hour even very close to departure.
    return 1800 if remaining > 3600 else 1200 if remaining > 1800 else 900


def due_kinds(now, arrival, prepare, departure, eta_s):
    now = local(now)
    if now >= arrival:
        return []
    kinds = []
    if now >= departure:
        kinds.append('departure_due')
    elif now >= departure - timedelta(minutes=5):
        kinds.append('departure_soon')
    if prepare <= now < departure:
        kinds.append('preparation_due')
    elif prepare - timedelta(minutes=5) <= now < prepare:
        kinds.append('preparation_soon')
    if now + timedelta(seconds=eta_s) > arrival:
        kinds.append('late_risk')
    return kinds
