"""
convect.ingest.generators.replay - Historical sensor log stream replayer.

Replays recorded observations from disk or an iterator while preserving original
inter-arrival time deltas, scaled by a user-configurable speed multiplier.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import time
from typing import Iterator, List, Optional
from ingest.protocol import Reading


class LogReplayer:
    """
    Replays a sequence of Readings with time pacing.
    """

    def __init__(self, speed_multiplier: float = 1.0, max_sleep_sec: float = 5.0) -> None:
        self.speed_multiplier = max(0.001, speed_multiplier)
        self.max_sleep_sec = max_sleep_sec
        self.total_replayed = 0

    def replay(self, readings: Iterator[Reading]) -> Iterator[Reading]:
        """
        Yield readings while respecting the original timestamp delta / speed_multiplier.
        """
        prev_orig_ts: Optional[int] = None
        prev_wall_time = time.time()

        for r in readings:
            if prev_orig_ts is not None:
                delta_ms = r.timestamp - prev_orig_ts
                if delta_ms > 0:
                    sleep_sec = (delta_ms / 1000.0) / self.speed_multiplier
                    sleep_sec = min(sleep_sec, self.max_sleep_sec)
                    if sleep_sec > 0.001:
                        time.sleep(sleep_sec)

            prev_orig_ts = r.timestamp
            self.total_replayed += 1
            yield r
