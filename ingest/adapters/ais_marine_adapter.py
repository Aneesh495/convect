"""
Convect Distributed Spatiotemporal Stream Engine
Module: ingest.adapters.ais_marine_adapter

Maritime Automatic Identification System (AIS) stream adapter.
Decodes vessel dynamic position reports, navigational status, speed over ground (SOG),
and courses into streaming geospatial observations.
"""

from typing import Iterator, Dict, Any, List, Optional
import json
from .base import BaseAdapter
from ..protocol import Reading, MetricType


class AISMarineAdapter(BaseAdapter):
    """
    Adapter for maritime vessel tracking streams (AIS NMEA 0183 / JSON telemetry).
    Maps vessel speed over ground (SOG in knots) or position into Convect Readings.
    """

    def __init__(self, metric_type: MetricType = MetricType.VELOCITY):
        super().__init__()
        self.metric_type = metric_type

    def parse_stream(self, stream: Any) -> Iterator[Reading]:
        """
        Parse stream or buffer, delegating to parse.
        """
        yield from self.parse(stream)

    def parse(self, raw_input: Any) -> Iterator[Reading]:
        """
        Parse raw input. Supports:
        1. JSON strings or list of AIS vessel status dicts
        2. CSV lines with format: mmsi,lat,lon,sog,cog,timestamp
        3. NMEA-like simplified AIS records
        """
        if isinstance(raw_input, (list, tuple)):
            for item in raw_input:
                yield from self._parse_single(item)
        elif isinstance(raw_input, str):
            trimmed = raw_input.strip()
            if trimmed.startswith("{") or trimmed.startswith("["):
                try:
                    parsed_json = json.loads(trimmed)
                    if isinstance(parsed_json, list):
                        for item in parsed_json:
                            yield from self._parse_single(item)
                    elif isinstance(parsed_json, dict):
                        yield from self._parse_single(parsed_json)
                except Exception:
                    pass
            else:
                for line in trimmed.splitlines():
                    yield from self._parse_line(line)
        elif isinstance(raw_input, dict):
            yield from self._parse_single(raw_input)

    def _parse_single(self, d: Dict[str, Any]) -> Iterator[Reading]:
        try:
            mmsi = str(d.get("mmsi") or d.get("MMSI") or "unknown_vessel")
            lat = float(d.get("lat") or d.get("latitude") or 0.0)
            lon = float(d.get("lon") or d.get("longitude") or 0.0)
            sog = float(d.get("sog") or d.get("speed") or d.get("speed_over_ground") or 0.0)
            ts = int(d.get("timestamp_ms") or d.get("timestamp") or 1600000000000)

            # Filter obvious invalid GPS positions
            if abs(lat) > 90.0 or abs(lon) > 180.0 or (lat == 0.0 and lon == 0.0):
                return

            yield Reading(
                sensor_id=f"vessel_{mmsi}",
                lat=lat,
                lon=lon,
                value=sog,
                timestamp_ms=ts,
                metric_type=self.metric_type
            )
        except (ValueError, TypeError):
            return

    def _parse_line(self, line: str) -> Iterator[Reading]:
        line = line.strip()
        if not line or line.startswith("#"):
            return

        parts = [p.strip() for p in line.split(",")]
        if len(parts) >= 4:
            try:
                mmsi = parts[0]
                lat = float(parts[1])
                lon = float(parts[2])
                sog = float(parts[3])
                ts = int(parts[4]) if len(parts) > 4 else 1600000000000

                yield Reading(
                    sensor_id=f"vessel_{mmsi}",
                    lat=lat,
                    lon=lon,
                    value=sog,
                    timestamp_ms=ts,
                    metric_type=self.metric_type
                )
            except (ValueError, IndexError):
                return
