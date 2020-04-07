"""
convect.ingest.adapters.base - Abstract base adapter for sensor stream ingestion.

Defines the contract for converting external data formats (GeoJSON, CSV, NOAA ISD,
NetCDF) into normalized Convect Reading instances ready for wire transmission.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import abc
import logging
from typing import Iterator, Optional, Dict, Any
from ingest.protocol import Reading

logger = logging.getLogger(__name__)


class BaseAdapter(abc.ABC):
    """
    Abstract base class for all ingestion source adapters.

    Subclasses implement the stream parsing logic for their respective formats.
    Common validation (lat/lon bounds, timestamp sanity, numeric value range) is
    handled uniformly by validate_reading().
    """

    def __init__(self, default_metric: str = "temperature", default_quality: int = 100) -> None:
        self.default_metric = default_metric
        self.default_quality = default_quality
        self.records_processed = 0
        self.records_valid = 0
        self.records_rejected = 0

    @abc.abstractmethod
    def parse_stream(self, stream: Any) -> Iterator[Reading]:
        """
        Parse an input stream (file-like object or line iterator) and yield valid Readings.

        Args:
            stream: Source stream (e.g., opened file, text buffer, or generator).

        Yields:
            Reading instances parsed and validated from the stream.
        """
        raise NotImplementedError

    def parse_file(self, filepath: str) -> Iterator[Reading]:
        """
        Convenience method to open and parse a file from disk.
        """
        with open(filepath, "r", encoding="utf-8") as fp:
            yield from self.parse_stream(fp)

    def validate_reading(self, reading: Reading) -> bool:
        """
        Perform geometric, temporal, and numeric sanity checks on a Reading.

        Returns:
            True if reading satisfies all constraints; False otherwise.
        """
        self.records_processed += 1

        # Check latitude [-90, 90]
        if not (-90.0 <= reading.latitude <= 90.0):
            logger.warning("Rejected reading with out-of-bounds latitude: %f", reading.latitude)
            self.records_rejected += 1
            return False

        # Check longitude [-180, 180]
        if not (-180.0 <= reading.longitude <= 180.0):
            logger.warning("Rejected reading with out-of-bounds longitude: %f", reading.longitude)
            self.records_rejected += 1
            return False

        # Check timestamp (non-zero, positive epoch milliseconds)
        if reading.timestamp <= 0:
            logger.warning("Rejected reading with invalid timestamp: %d", reading.timestamp)
            self.records_rejected += 1
            return False

        # Check numeric finite value
        if reading.value != reading.value:  # NaN check
            logger.warning("Rejected reading with NaN value")
            self.records_rejected += 1
            return False

        self.records_valid += 1
        return True

    def get_stats(self) -> Dict[str, int]:
        """Return adapter processing counters."""
        return {
            "processed": self.records_processed,
            "valid": self.records_valid,
            "rejected": self.records_rejected,
        }
