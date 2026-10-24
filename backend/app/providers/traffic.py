from typing import Protocol


class TrafficDataProvider(Protocol):
    def status(self) -> dict: ...


class UnavailableTrafficProvider:
    """No verified, licensed live feed configured. Never infer delay from map colors."""
    def status(self) -> dict:
        return {'configured': False, 'provider': None, 'status': 'unavailable',
                'provider_updated_at': None, 'motorcycle_supported': True,
                'message': 'Chưa có nguồn traffic realtime phù hợp. ETA chỉ dựa trên routing.'}
