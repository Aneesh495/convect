"""
Convect Distributed Spatiotemporal Stream Engine
Module: ingest.adapters.adsb_aviation_adapter

Aviation ADS-B (Automatic Dependent Surveillance - Broadcast) stream adapter.
Parses SBS-1 BaseStation CSV and JSON aircraft transponder telemetry (ICAO 24-bit address,
altitude, ground speed, track, latitude, longitude) into streaming geospatial observations.
"""

from typing import Iterator, Dict, Any, List, Optional
import json
from .base import BaseAdapter
from ..protocol import Reading, MetricType


class ADSBAviationAdapter(BaseAdapter):
    """
    Adapter for aviation ADS-B flight tracking feeds.
    Maps aircraft altitude or groundspeed into Convect Readings.
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
        1. JSON strings or list of aircraft status dicts (readsb/dump1090 format)
        2. SBS-1 BaseStation CSV lines (MSG,3,...)
        """
        if isinstance(raw_input, (list, tuple)):
            for item in raw_input:
                yield from self._parse_json_dict(item)
        elif isinstance(raw_input, str):
            trimmed = raw_input.strip()
            if trimmed.startswith("{") or trimmed.startswith("["):
                try:
                    parsed_json = json.loads(trimmed)
                    if isinstance(parsed_json, list):
                        for item in parsed_json:
                            yield from self._parse_json_dict(item)
                    elif isinstance(parsed_json, dict):
                        # dump1090 aircraft.json has an 'aircraft' list
                        if "aircraft" in parsed_json:
                            for ac in parsed_json["aircraft"]:
                                yield from self._parse_json_dict(ac)
                        else:
                            yield from self._parse_json_dict(parsed_json)
                except Exception:
                    pass
            else:
                for line in trimmed.splitlines():
                    yield from self._parse_sbs_line(line)
        elif isinstance(raw_input, dict):
            yield from self._parse_json_dict(raw_input)

    def _parse_json_dict(self, d: Dict[str, Any]) -> Iterator[Reading]:
        try:
            icao = str(d.get("hex") or d.get("icao") or "unknown_ac").upper()
            lat = float(d.get("lat") or 0.0)
            lon = float(d.get("lon") or 0.0)
            speed = float(d.get("speed") or d.get("gs") or 0.0)
            alt = float(d.get("alt_baro") or d.get("altitude") or 0.0)
            ts = int(d.get("timestamp_ms") or 1600000000000)

            if abs(lat) > 90.0 or abs(lon) > 180.0 or (lat == 0.0 and lon == 0.0):
                return

            val = alt if self.metric_type == MetricType.PRESSURE else speed

            yield Reading(
                sensor_id=f"flight_{icao}",
                lat=lat,
                lon=lon,
                value=val,
                timestamp_ms=ts,
                metric_type=self.metric_type
            )
        except (ValueError, TypeError):
            return

    def _parse_sbs_line(self, line: str) -> Iterator[Reading]:
        line = line.strip()
        if not line or not line.startswith("MSG"):
            return

        parts = [p.strip() for p in line.split(",")]
        # SBS-1 format: MSG,transmission_type,...,icao,...,alt,speed,track,lat,lon
        if len(parts) >= 16:
            try:
                transmission_type = parts[1]
                icao = parts[4].upper()

                if transmission_type == "3":  # Airborne position message
                    alt = float(parts[11]) if parts[11] else 0.0
                    lat = float(parts[14]) if parts[14] else 0.0
                    lon = float(parts[15]) if parts[15] else 0.0

                    if abs(lat) > 0.0001 or abs(lon) > 0.0001:
                        yield Reading(
                            sensor_id=f"flight_{icao}",
                            lat=lat,
                            lon=lon,
                            value=alt,
                            timestamp_ms=1600000000000,
                            metric_type=self.metric_type
                        )
            except (ValueError, IndexError):
                return
