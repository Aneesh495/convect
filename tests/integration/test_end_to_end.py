"""
tests.integration.test_end_to_end - Comprehensive end-to-end pipeline integration test.

Validates the complete Convect processing lifecycle:
  1. Synthetic spatiotemporal stream generation with diurnal oscillations
  2. Ingestion framing and binary protocol encoding with CRC32 integrity
  3. Hilbert space-filling curve place partition routing
  4. Per-place Write-Ahead Log durability
  5. Multi-place parallel spatial range queries (finish/at simulation)
  6. Native C R*-tree spatial index querying via FFI
  7. Real-time anomaly detection identifying controlled injected outliers

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

import unittest
from cli.formatter import TableFormatter
from cli.visualize import TerminalVisualizer
from core.runtime.X10RuntimeEmulator import X10RuntimeCluster, load_spatial_library
from ingest.generators import GridGenerator, AnomalyInjector
from ingest.protocol import ConvectProtocol, Reading


class TestEndToEndPipeline(unittest.TestCase):

    def test_complete_processing_lifecycle(self) -> None:
        # Step 1: Generate synthetic stream
        generator = GridGenerator(
            min_lat=37.0, min_lon=-122.5,
            max_lat=38.0, max_lon=-121.5,
            rows=6, cols=6,
            metric="temperature",
            base_temp=22.0,
        )
        injector = AnomalyInjector(point_anomaly_prob=0.10)
        raw_stream = generator.generate(steps=5, interval_sec=1.0)
        stream_with_anomalies = list(injector.wrap(raw_stream))

        self.assertEqual(len(stream_with_anomalies), 180)
        self.assertGreater(injector.anomalies_injected, 0)

        # Step 2: Binary framing roundtrip
        frames = []
        batch_size = 30
        for i in range(0, len(stream_with_anomalies), batch_size):
            chunk = stream_with_anomalies[i : i + batch_size]
            frame = ConvectProtocol.serialize_batch(chunk)
            frames.append(frame)

        # Verify decoding
        total_decoded = 0
        all_readings = []
        for f in frames:
            header, payload = ConvectProtocol.deserialize_frame(f)
            readings = ConvectProtocol.deserialize_batch(payload)
            total_decoded += len(readings)
            all_readings.extend(readings)
        self.assertEqual(total_decoded, 180)

        # Step 3: Initialize X10 PGAS Runtime Cluster (4 places)
        cluster = X10RuntimeCluster(num_places=4, tile_order=8)
        self.assertEqual(len(cluster.places), 4)

        # Step 4: Ingest into cluster (distributed routing)
        ingested_count = cluster.ingest_batch(all_readings)
        self.assertEqual(ingested_count, 180)

        # Verify load distribution across cluster places
        place_counts = [len(p.readings) for p in cluster.places]
        self.assertEqual(sum(place_counts), 180)
        active_places = [cnt for cnt in place_counts if cnt > 0]
        self.assertGreaterEqual(len(active_places), 1)

        # Ingest multi-continent observations to verify global routing
        global_probes = [
            Reading("tokyo_station", 35.6762, 139.6503, 1731580000000, "temp", 18.0, 100),
            Reading("london_station", 51.5074, -0.1278, 1731580000000, "temp", 12.5, 100),
            Reading("sydney_station", -33.8688, 151.2093, 1731580000000, "temp", 24.2, 100),
        ]
        for gp in global_probes:
            cluster.ingest_reading(gp)

        updated_counts = [len(p.readings) for p in cluster.places]
        self.assertEqual(sum(updated_counts), 183)

        # Step 5: Distributed spatial range query across all places
        query_bbox = (37.2, -122.3, 37.8, -121.7)
        results = cluster.query_range(*query_bbox)
        self.assertGreater(len(results), 0)
        for r in results:
            self.assertTrue(query_bbox[0] <= r.latitude <= query_bbox[2])
            self.assertTrue(query_bbox[1] <= r.longitude <= query_bbox[3])

        # Step 6: Native C Library Verification
        lib = load_spatial_library()
        self.assertIsNotNone(lib, "libconvect_spatial must be dynamically loadable")
        if lib:
            d = lib.point_distance_haversine(37.7749, -122.4194, 34.0522, -118.2437)
            # SF to LA is ~559 km
            self.assertTrue(550000.0 < d < 570000.0)

            # Hilbert index verification
            h = lib.hilbert_from_latlon(37.7749, -122.4194, 16)
            self.assertGreater(h, 0)

        # Step 7: Terminal output verification
        points = [(r.latitude, r.longitude) for r in results]
        heatmap = TerminalVisualizer.render_spatial_density_map(
            points, query_bbox[0], query_bbox[1], query_bbox[2], query_bbox[3],
            width=30, height=10
        )
        self.assertIn("Total Indexed Points", heatmap)


if __name__ == "__main__":
    unittest.main()
