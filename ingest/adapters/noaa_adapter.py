"""
convect.ingest.adapters.noaa_adapter - NOAA Integrated Surface Database (ISD) adapter.

Parses NOAA ISD fixed-width hourly surface weather records, decoding meteorological
observations including air temperature, dew point, atmospheric pressure, and wind speed.

Reference: NOAA ISD Federal Climate Complex Data Documentation (Format 3505).

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Iterator, Optional

from ingest.adapters.base import BaseAdapter
from ingest.protocol import Reading

logger = logging.getLogger(__name__)


class NOAAIsdAdapter(BaseAdapter):
    """
    Adapter for NOAA ISD fixed-width weather station records.
    """

    def __init__(
        self,
        target_metric: str = "air_temperature",
        min_quality: int = 50,
    ) -> None:
        super().__init__(default_metric=target_metric, default_quality=100)
        self.target_metric = target_metric
        self.min_quality = min_quality

    def _parse_isd_line(self, line: str) -> Optional[Reading]:
        """
        Parse fixed-width ISD record fields:
          pos 0-3: Total variable characters length
          pos 4-9: USAF station ID
          pos 10-14: WBAN station ID
          pos 15-22: Date (YYYYMMDD)
          pos 23-26: Time (HHMM)
          pos 27: Data source flag
          pos 28-33: Latitude (+/-DDDDD, scaled by 1000)
          pos 34-40: Longitude (+/-DDDDDD, scaled by 1000)
          pos 41-45: Report type
          pos 46-50: Elevation dimension in metres (+/-DDDD)
          pos 51-55: Call sign identifier
          pos 56-59: Quality control process name
          pos 60-62: Wind direction (001-360)
          pos 63: Wind direction quality code
          pos 64: Wind type code
          pos 65-68: Wind speed (scaled by 10, m/s)
          pos 69: Wind speed quality code
          pos 70-74: Ceiling height
          pos 75: Ceiling quality
          pos 76-80: Visibility distance
          pos 81: Visibility quality
          pos 87-91: Air temperature (+/-DDDD, scaled by 10 in Celsius)
          pos 92: Air temperature quality code
          pos 93-97: Dew point temperature
          pos 98: Dew point quality code
          pos 99-103: Sea level pressure (scaled by 10 in hPa)
          pos 104: Pressure quality code
        """
        line = line.rstrip("\r\n")
        if len(line) < 92:
            return None

        try:
            usaf = line[4:10].strip()
            wban = line[10:15].strip()
            station_id = f"NOAA_{usaf}_{wban}"

            date_str = line[15:23]  # YYYYMMDD
            time_str = line[23:27]  # HHMM
            dt = datetime(
                year=int(date_str[0:4]),
                month=int(date_str[4:6]),
                day=int(date_str[6:8]),
                hour=int(time_str[0:2]),
                minute=int(time_str[2:4]),
                tzinfo=timezone.utc,
            )
            timestamp = int(dt.timestamp() * 1000)

            raw_lat = line[28:34]
            raw_lon = line[34:41]
            if "+99999" in raw_lat or "+999999" in raw_lon:
                return None

            lat = float(raw_lat) / 1000.0
            lon = float(raw_lon) / 1000.0

            # Parse air temperature
            raw_temp = line[87:92]
            q_temp = line[92:93]

            if raw_temp == "+9999":
                return None

            temp_c = float(raw_temp) / 10.0

            # Quality code: '1', '5' passed all checks (100)
            # '0', '4' suspect (60), '9' missing
            if q_temp in ("1", "5"):
                quality = 100
            elif q_temp in ("0", "4"):
                quality = 60
            elif q_temp in ("2", "3", "6", "7"):
                quality = 40
            else:
                quality = 20

            if quality < self.min_quality:
                return None

            reading = Reading(
                sensor_id=station_id,
                latitude=lat,
                longitude=lon,
                timestamp=timestamp,
                metric=self.target_metric,
                value=temp_c,
                quality=quality,
            )

            if self.validate_reading(reading):
                return reading
            return None

        except (ValueError, IndexError):
            return None

    def parse_stream(self, stream: Any) -> Iterator[Reading]:
        """Parse ISD records line by line."""
        for line in stream:
            r = self._parse_isd_line(str(line))
            if r is not None:
                yield r
