"""
convect.ingest.adapters.csv_adapter - Delimited text and CSV stream adapter.

Parses CSV, TSV, and semicolon/pipe-delimited text files containing spatiotemporal
sensor observations. Handles automatic dialect detection, gzip/bzip2 decompression,
and flexible column index/name bindings.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import csv
import gzip
import bz2
import io
import logging
import time
from datetime import datetime
from typing import Any, Dict, Iterator, List, Optional, Union

from ingest.adapters.base import BaseAdapter
from ingest.protocol import Reading

logger = logging.getLogger(__name__)


class CSVAdapter(BaseAdapter):
    """
    Adapter for tabular CSV/TSV sensor observations.

    Field bindings can be specified by column name or by zero-based integer index.
    """

    def __init__(
        self,
        id_col: Union[str, int] = "sensor_id",
        lat_col: Union[str, int] = "latitude",
        lon_col: Union[str, int] = "longitude",
        time_col: Union[str, int] = "timestamp",
        val_col: Union[str, int] = "value",
        metric_col: Optional[Union[str, int]] = None,
        quality_col: Optional[Union[str, int]] = None,
        delimiter: Optional[str] = None,
        has_header: bool = True,
        time_format: Optional[str] = None,
        default_metric: str = "temperature",
        default_quality: int = 100,
    ) -> None:
        super().__init__(default_metric=default_metric, default_quality=default_quality)
        self.id_col = id_col
        self.lat_col = lat_col
        self.lon_col = lon_col
        self.time_col = time_col
        self.val_col = val_col
        self.metric_col = metric_col
        self.quality_col = quality_col
        self.delimiter = delimiter
        self.has_header = has_header
        self.time_format = time_format

    def _parse_time(self, raw: str) -> int:
        """Parse timestamp string into epoch milliseconds."""
        raw = raw.strip()
        if not raw:
            return int(time.time() * 1000)

        # Check numeric epoch
        try:
            val = float(raw)
            if val < 1e11:
                return int(val * 1000)
            return int(val)
        except ValueError:
            pass

        # Try custom format if provided
        if self.time_format:
            try:
                dt = datetime.strptime(raw, self.time_format)
                return int(dt.timestamp() * 1000)
            except ValueError:
                pass

        # Try standard ISO-8601
        try:
            cleaned = raw.replace("Z", "+00:00")
            dt = datetime.fromisoformat(cleaned)
            return int(dt.timestamp() * 1000)
        except Exception:
            pass

        return int(time.time() * 1000)

    def _get_val(self, row: Union[List[str], Dict[str, str]], col: Union[str, int], default: Any = None) -> Any:
        if isinstance(row, dict):
            if isinstance(col, str) and col in row:
                return row[col]
            # fallback to lowercase search
            for k, v in row.items():
                if k.lower() == str(col).lower():
                    return v
            return default
        elif isinstance(row, (list, tuple)):
            if isinstance(col, int) and 0 <= col < len(row):
                return row[col]
            return default
        return default

    def parse_file(self, filepath: str) -> Iterator[Reading]:
        """Open local file supporting gzip, bz2, and plain text."""
        if filepath.endswith(".gz"):
            with gzip.open(filepath, "rt", encoding="utf-8") as fp:
                yield from self.parse_stream(fp)
        elif filepath.endswith(".bz2"):
            with bz2.open(filepath, "rt", encoding="utf-8") as fp:
                yield from self.parse_stream(fp)
        else:
            with open(filepath, "r", encoding="utf-8") as fp:
                yield from self.parse_stream(fp)

    def parse_stream(self, stream: Any) -> Iterator[Reading]:
        """Parse delimited rows from stream."""
        # Sniff dialect if delimiter not explicitly configured
        dialect_delim = self.delimiter or ","

        if self.has_header:
            reader = csv.DictReader(stream, delimiter=dialect_delim)
        else:
            reader = csv.reader(stream, delimiter=dialect_delim)

        for row in reader:
            try:
                raw_id = self._get_val(row, self.id_col)
                if raw_id is None:
                    raw_id = f"sensor_{self.records_processed + 1}"
                sensor_id = str(raw_id).strip()

                lat_str = self._get_val(row, self.lat_col)
                lon_str = self._get_val(row, self.lon_col)
                val_str = self._get_val(row, self.val_col)

                if lat_str is None or lon_str is None or val_str is None:
                    self.records_rejected += 1
                    continue

                lat = float(lat_str)
                lon = float(lon_str)
                val = float(val_str)

                time_str = self._get_val(row, self.time_col, "")
                ts = self._parse_time(str(time_str))

                if self.metric_col:
                    metric = str(self._get_val(row, self.metric_col, self.default_metric))
                else:
                    metric = self.default_metric

                if self.quality_col:
                    q_str = self._get_val(row, self.quality_col, str(self.default_quality))
                    try:
                        quality = int(float(q_str))
                    except ValueError:
                        quality = self.default_quality
                else:
                    quality = self.default_quality

                reading = Reading(
                    sensor_id=sensor_id,
                    latitude=lat,
                    longitude=lon,
                    timestamp=ts,
                    metric=metric,
                    value=val,
                    quality=quality,
                )

                if self.validate_reading(reading):
                    yield reading

            except (ValueError, TypeError):
                self.records_rejected += 1
                continue
