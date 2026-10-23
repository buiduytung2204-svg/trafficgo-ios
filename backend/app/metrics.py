"""Bounded process-local diagnostics. Never retain URLs, coordinates or credentials."""
from collections import defaultdict, deque
from contextvars import ContextVar
from threading import Lock
import math

request_upstream = ContextVar('request_upstream', default=None)


class Metrics:
    def __init__(self):
        self.lock = Lock()
        self.samples = defaultdict(lambda: deque(maxlen=2000))
        self.counts = defaultdict(lambda: {'requests': 0, 'errors': 0, 'rate_limited': 0})

    def record(self, name, milliseconds, status):
        with self.lock:
            self.samples[name].append(milliseconds)
            counts = self.counts[name]
            counts['requests'] += 1
            counts['errors'] += status >= 400
            counts['rate_limited'] += status == 429
        if name.startswith(('tomtom.', 'valhalla.', 'geoapify.')):
            current = request_upstream.get()
            if current is not None:
                current.append(milliseconds)

    def snapshot(self):
        with self.lock:
            result = {}
            for name, counts in self.counts.items():
                samples = sorted(self.samples[name])
                def percentile(p):
                    return round(samples[max(0, math.ceil(len(samples)*p)-1)], 3)
                result[name] = {**counts, 'sample_count': len(samples),
                    'p50_ms': percentile(.5), 'p95_ms': percentile(.95),
                    'error_rate': counts['errors']/counts['requests']}
            return result


metrics = Metrics()
