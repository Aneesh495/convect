"""
tests.python.test_generators - Unit tests for synthetic stream generators and anomaly injectors.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

import unittest
from ingest.generators import (
    GridGenerator,
    ClusterGenerator,
    RandomWalkGenerator,
    AnomalyInjector,
    LogReplayer,
)
from ingest.protocol import Reading


class TestGenerators(unittest.TestCase):

    def test_grid_generator_dimensions(self) -> None:
        gen = GridGenerator(
            min_lat=30.0, min_lon=-120.0,
            max_lat=40.0, max_lon=-110.0,
            rows=5, cols=4,
            metric="temperature",
        )
        self.assertEqual(len(gen.stations), 20)

        # 3 steps should yield 60 readings
        readings = list(gen.generate(steps=3, interval_sec=0.01))
        self.assertEqual(len(readings), 60)

        # Check bounds
        for r in readings:
            self.assertTrue(30.0 <= r.latitude <= 40.0)
            self.assertTrue(-120.0 <= r.longitude <= -110.0)
            self.assertEqual(r.metric, "temperature")

    def test_cluster_generator(self) -> None:
        centers = [(37.77, -122.41), (34.05, -118.24)]
        gen = ClusterGenerator(centers=centers, sensors_per_cluster=10)
        self.assertEqual(len(gen.stations), 20)

        readings = list(gen.generate(steps=2, interval_sec=0.01))
        self.assertEqual(len(readings), 40)

    def test_random_walk_generator(self) -> None:
        gen = RandomWalkGenerator(num_sensors=5, start_lat=37.0, start_lon=-122.0)
        readings = list(gen.generate(steps=10, interval_sec=0.01))
        self.assertEqual(len(readings), 50)

    def test_anomaly_injector(self) -> None:
        gen = GridGenerator(min_lat=37.0, min_lon=-122.0, max_lat=38.0, max_lon=-121.0, rows=4, cols=4)
        clean_stream = gen.generate(steps=10, interval_sec=0.01)

        injector = AnomalyInjector(point_anomaly_prob=0.30)
        anomalous_stream = list(injector.wrap(clean_stream))

        self.assertEqual(len(anomalous_stream), 160)
        self.assertGreater(injector.anomalies_injected, 0)

        # Injected anomalies should have quality=20
        degraded = [r for r in anomalous_stream if r.quality == 20]
        self.assertEqual(len(degraded), injector.anomalies_injected)

    def test_log_replayer(self) -> None:
        readings = [
            Reading("s1", 37.0, -122.0, 1000, "temp", 20.0, 100),
            Reading("s1", 37.0, -122.0, 1050, "temp", 20.5, 100),
            Reading("s1", 37.0, -122.0, 1100, "temp", 21.0, 100),
        ]
        replayer = LogReplayer(speed_multiplier=100.0)
        replayed = list(replayer.replay(readings))
        self.assertEqual(len(replayed), 3)
        self.assertEqual(replayer.total_replayed, 3)


if __name__ == "__main__":
    unittest.main()
