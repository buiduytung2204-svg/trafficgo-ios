"""Coalesce concurrent identical requests; no tile cache or post-response retention."""
import asyncio


class TileRequests:
    def __init__(self):
        self.pending = {}

    async def get(self, key, fetch):
        task = self.pending.get(key)
        joined = task is not None
        if task is None:
            task = asyncio.create_task(fetch())
            self.pending[key] = task
            def finished(done):
                if self.pending.get(key) is done:
                    self.pending.pop(key, None)
                # Consume errors even if all callers disconnected.
                if not done.cancelled():
                    done.exception()
            task.add_done_callback(finished)
        return await asyncio.shield(task), joined
