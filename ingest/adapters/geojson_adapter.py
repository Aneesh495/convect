"""
convect.ingest.adapters.geojson_adapter - RFC 7946 GeoJSON stream adapter.

Parses GeoJSON FeatureCollection documents and newline-delimited GeoJSON streams
(GeoJSON Text Sequences / RFC 8142), extracting Point geometries and mapping
feature properties to normalized Reading objects.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import json
import logging
import time
from typing import Any, Dict, Iterator, Optional, Union

from ingest.adapters.base import BaseAdapter
from ingest.protocol import Reading

logger = logging.getLogger(__name__)


class GeoJSONAdapter(BaseAdapter):
    """
    Adapter for GeoJSON Point features.

    Supports configurable property extraction via dot-notation keys:
      - id_prop: Key containing the sensor identifier (default: "id" or "sensor_id")
      - time_prop: Key containing observation timestamp (ISO-8601 or epoch millis)
      - metric_prop: Key containing the metric name
      - value_prop: Key containing the numeric measurement
      - quality_prop: Key containing optional quality indicator (0-100)
    """

    def __init__(
        self,
        id_prop: str = "sensor_id",
        time_prop: str = "timestamp",
        metric_prop: Optional[str] = None,
        value_prop: str = "value",
        quality_prop: str = "quality",
        default_metric: str = "environmental_reading",
        default_quality: int = 100,
    ) -> None:
        super().__init__(default_metric=default_metric, default_quality=default_quality)
        self.id_prop = id_prop
        self.time_prop = time_prop
        self.metric_prop = metric_prop
        self.value_prop = value_prop
        self.quality_prop = quality_prop

    def _resolve_prop(self, props: Dict[str, Any], key: str) -> Any:
        """Resolve a potentially nested property using dot notation."""
        parts = key.split(".")
        cur = props
        for p in parts:
            if isinstance(cur, dict) and p in cur:
                cur = cur[p]
            else:
                return None
        return cur

    def _parse_timestamp(self, raw_time: Any) -> int:
        """Parse raw time into integer milliseconds since Unix epoch."""
        if raw_time is None:
            return int(time.time() * 1000)
        if isinstance(raw_time, (int, float)):
            # If timestamp is in seconds (e.g. < 1e11), convert to milliseconds
            if raw_time < 1e11:
                return int(raw_time * 1000)
            return int(raw_time)
        if isinstance(raw_time, str):
            try:
                # Fast ISO 8601 parsing
                from datetime import datetime
                cleaned = raw_time.replace("Z", "+00:00")
                dt = datetime.fromisoformat(cleaned)
                return int(dt.timestamp() * 1000)
            except Exception:
                return int(time.time() * 1000)
        return int(time.time() * 1000)

    def _feature_to_reading(self, feature: Dict[str, Any]) -> Optional[Reading]:
        """Convert a GeoJSON Feature dictionary into a Reading."""
        if not isinstance(feature, dict):
            return None

        geom = feature.get("geometry")
        if not geom or geom.get("type") != "Point":
            return None

        coords = geom.get("coordinates")
        if not coords or len(coords) < 2:
            return None

        # GeoJSON coordinates are [longitude, latitude, (elevation)]
        lon = float(coords[0])
        lat = float(coords[1])

        props = feature.get("properties") or {}

        # Resolve sensor identifier
        sensor_id = self._resolve_prop(props, self.id_prop)
        if sensor_id is None:
            sensor_id = feature.get("id") or f"sensor_{self.records_processed + 1}"
        sensor_id = str(sensor_id)

        # Resolve timestamp
        raw_time = self._resolve_prop(props, self.time_prop)
        ts = self._parse_timestamp(raw_time)

        # Resolve metric name
        if self.metric_prop:
            metric = str(self._resolve_prop(props, self.metric_prop) or self.default_metric)
        else:
            metric = self.default_metric

        # Resolve numeric measurement
        raw_val = self._resolve_prop(props, self.value_prop)
        if raw_val is None:
            return None
        try:
            val = float(raw_val)
        except (ValueError, TypeError):
            return None

        # Resolve quality
        raw_q = self._resolve_prop(props, self.quality_prop)
        quality = int(raw_q) if raw_q is not None else self.default_quality

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
            return reading
        return None

    def parse_stream(self, stream: Any) -> Iterator[Reading]:
        """
        Parse either a complete GeoJSON document or newline-delimited GeoJSON features.
        """
        # If stream has read(), try to detect if it's a whole FeatureCollection or line-by-line
        first_line = None
        if hasattr(stream, "readline"):
            first_line = stream.readline()

        if first_line:
            stripped = first_line.strip()
            # If starting with '{' and contains FeatureCollection, parse entire stream as JSON
            if "FeatureCollection" in stripped or (stripped.startswith("{") and not stripped.endswith("}")):
                full_text = first_line + stream.read()
                try:
                    data = json.loads(full_text)
                    if data.get("type") == "FeatureCollection":
                        for feat in data.get("features", []):
                            r = self._feature_to_reading(feat)
                            if r is not None:
                                yield r
                    elif data.get("type") == "Feature":
                        r = self._feature_to_reading(data)
                        if r is not None:
                            yield r
                    return
                except json.JSONDecodeError as err:
                    logger.error("Failed to decode GeoJSON document: %s", err)
                    return
            else:
                # Line-delimited stream
                try:
                    data = json.loads(stripped)
                    r = self._feature_to_reading(data)
                    if r is not None:
                        yield r
                except json.JSONDecodeError:
                    pass

                for line in stream:
                    line_s = line.strip()
                    if not line_s:
                        continue
                    try:
                        feat_dict = json.loads(line_s)
                        r = self._feature_to_reading(feat_dict)
                        if r is not None:
                            yield r
                    except json.JSONDecodeError:
                        self.records_rejected += 1
                        continue
        else:
            # Iterable of strings
            for line in stream:
                line_s = line.strip()
                if not line_s:
                    continue
                try:
                    feat_dict = json.loads(line_s)
                    r = self._feature_to_reading(feat_dict)
                    if r is not None:
                        yield r
                except json.JSONDecodeError:
                    self.records_rejected += 1
                    continue
