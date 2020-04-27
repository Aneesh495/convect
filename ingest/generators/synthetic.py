"""
convect.ingest.generators.synthetic - Synthetic spatiotemporal sensor stream generator.

Generates realistic environmental sensor observation streams with spatial autocorrelation,
diurnal cycle oscillations, sensor drifts, and controlled anomaly injections for
benchmarking and automated test verification.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import math
import random
import time
from dataclasses import dataclass
from typing import Iterator, List, Optional, Tuple

from ingest.protocol import Reading


@dataclass
class SensorStation:
    station_id: str
    latitude: float
    longitude: float
    base_val: float
    amplitude: float
    phase_offset: float
    noise_sigma: float
    drift_rate: float = 0.0


class GridGenerator:
    """
    Generates a uniform 2D grid of stationary environmental sensors.
    """

    def __init__(
        self,
        min_lat: float,
        min_lon: float,
        max_lat: float,
        max_lon: float,
        rows: int = 10,
        cols: int = 10,
        metric: str = "temperature",
        base_temp: float = 20.0,
    ) -> None:
        self.metric = metric
        self.stations: List[SensorStation] = []

        lat_step = (max_lat - min_lat) / max(1, rows - 1) if rows > 1 else 0.0
        lon_step = (max_lon - min_lon) / max(1, cols - 1) if cols > 1 else 0.0

        idx = 1
        for r in range(rows):
            cur_lat = min_lat + r * lat_step
            for c in range(cols):
                cur_lon = min_lon + c * lon_step
                sid = f"grid_{idx:04d}"
                # Base temp with subtle latitude gradient
                b_val = base_temp - (cur_lat - min_lat) * 0.4
                st = SensorStation(
                    station_id=sid,
                    latitude=cur_lat,
                    longitude=cur_lon,
                    base_val=b_val,
                    amplitude=6.0,
                    phase_offset=random.uniform(0, 2 * math.pi),
                    noise_sigma=0.3,
                )
                self.stations.append(st)
                idx += 1

    def generate(self, steps: int = 100, interval_sec: float = 1.0) -> Iterator[Reading]:
        """Generate sensor readings across time steps."""
        start_ts = int(time.time() * 1000)

        for step in range(steps):
            step_ts = start_ts + int(step * interval_sec * 1000)
            # 24-hour diurnal cycle simulated in steps
            time_fraction = (step % 24) / 24.0 * 2 * math.pi

            for st in self.stations:
                diurnal = st.amplitude * math.sin(time_fraction + st.phase_offset)
                noise = random.gauss(0, st.noise_sigma)
                val = st.base_val + diurnal + noise

                yield Reading(
                    sensor_id=st.station_id,
                    latitude=st.latitude,
                    longitude=st.longitude,
                    timestamp=step_ts,
                    metric=self.metric,
                    value=round(val, 2),
                    quality=100,
                )


class ClusterGenerator:
    """
    Generates Gaussian clusters of sensor stations around specified anchor coordinates.
    """

    def __init__(
        self,
        centers: List[Tuple[float, float]],
        sensors_per_cluster: int = 25,
        cluster_radius_deg: float = 0.05,
        metric: str = "pm25",
        base_val: float = 12.0,
    ) -> None:
        self.metric = metric
        self.stations: List[SensorStation] = []

        sid_counter = 1
        for c_idx, (clat, clon) in enumerate(centers):
            for _ in range(sensors_per_cluster):
                # Box-Muller Gaussian jitter around center
                d_lat = random.gauss(0, cluster_radius_deg * 0.5)
                d_lon = random.gauss(0, cluster_radius_deg * 0.5)
                st = SensorStation(
                    station_id=f"cluster_{c_idx+1}_{sid_counter:04d}",
                    latitude=clat + d_lat,
                    longitude=clon + d_lon,
                    base_val=base_val + random.uniform(-2.0, 2.0),
                    amplitude=3.0,
                    phase_offset=random.uniform(0, math.pi),
                    noise_sigma=0.5,
                )
                self.stations.append(st)
                sid_counter += 1

    def generate(self, steps: int = 50, interval_sec: float = 1.0) -> Iterator[Reading]:
        start_ts = int(time.time() * 1000)

        for step in range(steps):
            step_ts = start_ts + int(step * interval_sec * 1000)
            for st in self.stations:
                noise = random.gauss(0, st.noise_sigma)
                val = max(0.0, st.base_val + noise)
                yield Reading(
                    sensor_id=st.station_id,
                    latitude=st.latitude,
                    longitude=st.longitude,
                    timestamp=step_ts,
                    metric=self.metric,
                    value=round(val, 2),
                    quality=100,
                )


class RandomWalkGenerator:
    """
    Simulates mobile / drifting sensor nodes (e.g. oceanic buoys, drones, balloons).
    """

    def __init__(
        self,
        num_sensors: int = 10,
        start_lat: float = 37.0,
        start_lon: float = -122.0,
        step_sigma_deg: float = 0.002,
        metric: str = "water_salinity",
    ) -> None:
        self.step_sigma_deg = step_sigma_deg
        self.metric = metric
        self.sensors: List[Dict[str, Any]] = []

        for i in range(num_sensors):
            self.sensors.append({
                "id": f"mobile_{i+1:03d}",
                "lat": start_lat + random.uniform(-0.1, 0.1),
                "lon": start_lon + random.uniform(-0.1, 0.1),
                "val": 35.0 + random.uniform(-0.5, 0.5),
            })

    def generate(self, steps: int = 100, interval_sec: float = 1.0) -> Iterator[Reading]:
        start_ts = int(time.time() * 1000)

        for step in range(steps):
            step_ts = start_ts + int(step * interval_sec * 1000)
            for s in self.sensors:
                # Random walk step
                s["lat"] += random.gauss(0, self.step_sigma_deg)
                s["lon"] += random.gauss(0, self.step_sigma_deg)
                s["val"] += random.gauss(0, 0.05)

                yield Reading(
                    sensor_id=s["id"],
                    latitude=s["lat"],
                    longitude=s["lon"],
                    timestamp=step_ts,
                    metric=self.metric,
                    value=round(s["val"], 3),
                    quality=100,
                )


class AnomalyInjector:
    """
    Decorator / wrapper stream generator that injects synthetic anomalies into clean streams:
      - Point anomaly: sudden high or low measurement spike
      - Drift anomaly: linear sensor calibration drift
      - Contextual anomaly: anomalous value relative to local spatial neighbors
      - Collective anomaly: sustained abnormal plateau
    """

    def __init__(
        self,
        point_anomaly_prob: float = 0.02,
        point_anomaly_scale: float = 5.0,
        drift_rate_per_sec: float = 0.1,
    ) -> None:
        self.point_anomaly_prob = point_anomaly_prob
        self.point_anomaly_scale = point_anomaly_scale
        self.drift_rate_per_sec = drift_rate_per_sec
        self.drift_accumulators: Dict[str, float] = {}
        self.anomalies_injected = 0

    def wrap(self, reading_stream: Iterator[Reading]) -> Iterator[Reading]:
        """
        Wraps an input reading generator and injects anomalies.
        """
        for r in reading_stream:
            val = r.value
            quality = r.quality

            # Check point anomaly
            if random.random() < self.point_anomaly_prob:
                spike_sign = 1.0 if random.random() > 0.5 else -1.0
                val += spike_sign * (abs(val) * self.point_anomaly_scale + 10.0)
                quality = 20  # Degradation flag
                self.anomalies_injected += 1

            # Check drift accumulation
            if r.sensor_id in self.drift_accumulators:
                self.drift_accumulators[r.sensor_id] += self.drift_rate_per_sec
                val += self.drift_accumulators[r.sensor_id]

            yield Reading(
                sensor_id=r.sensor_id,
                latitude=r.latitude,
                longitude=r.longitude,
                timestamp=r.timestamp,
                metric=r.metric,
                value=round(val, 2),
                quality=quality,
            )
