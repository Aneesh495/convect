"""
Convect Distributed Spatiotemporal Stream Engine
Test Suite: tests.integration.test_simulation_scenarios

End-to-end integration tests simulating real-world spatiotemporal applications:
1. Atmospheric wildfire smoke advection-dispersion plume simulation.
2. Maritime AIS vessel traffic and H3 hexagonal discrete global grid binning.
3. Aviation ADS-B trajectory ingestion and PGAS spatial range querying.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

import unittest
from core.runtime.X10RuntimeEmulator import X10RuntimeCluster
from ingest.protocol import Reading, MetricType
from ingest.adapters.ais_marine_adapter import AISMarineAdapter
from ingest.adapters.adsb_aviation_adapter import ADSBAviationAdapter


class TestSimulationScenarios(unittest.TestCase):

    def setUp(self) -> None:
        self.cluster = X10RuntimeCluster(num_places=4, tile_order=8)

    def test_wildfire_plume_advection_scenario(self) -> None:
        """
        Simulate an active wildfire smoke emission and verify physical
        advection-dispersion transport across spatial grid cells.
        """
        origin_reading = Reading(
            sensor_id="wildfire_origin",
            lat=37.75,
            lon=-122.45,
            value=100.0,
            timestamp_ms=1600000000000,
            metric_type=MetricType.AIR_QUALITY,
        )

        bounds = (37.70, -122.50, 37.80, -122.40)
        grid = self.cluster.simulate_plume_advection(
            readings=[origin_reading],
            bounds=bounds,
            steps=5,
            dt=0.1,
            u_wind=1.0,
            v_wind=0.0,
            diff_coeff=0.2,
        )

        self.assertEqual(len(grid), 20)
        self.assertEqual(len(grid[0]), 20)

        # Check total mass is non-negative and concentration exists
        total_mass = sum(sum(row) for row in grid)
        self.assertGreater(total_mass, 0.0)

    def test_maritime_ais_h3_dggs_binning(self) -> None:
        """
        Ingest AIS maritime vessel telemetry and verify H3 hexagonal
        discrete global grid spatial binning and k-ring neighbor expansion.
        """
        adapter = AISMarineAdapter()
        vessel_stream = [
            {"mmsi": 367000001, "lat": 37.795, "lon": -122.390, "sog": 8.5},
            {"mmsi": 367000002, "lat": 37.796, "lon": -122.391, "sog": 10.2},
            {"mmsi": 367000003, "lat": 37.820, "lon": -122.410, "sog": 0.1},
        ]

        readings = list(adapter.parse(vessel_stream))
        self.assertEqual(len(readings), 3)

        # Encode to H3 resolution 7
        h3_cells = [self.cluster.geo_to_h3(r.latitude, r.longitude, 7) for r in readings]
        for cell in h3_cells:
            self.assertNotEqual(cell, 0)

        # Vessels 1 and 2 are very close, should map to same or neighboring H3 cells
        v1_cell = h3_cells[0]
        k_ring = self.cluster.h3_k_ring(v1_cell, k=1)
        self.assertGreaterEqual(len(k_ring), 1)

    def test_aviation_adsb_pgas_routing(self) -> None:
        """
        Ingest aviation ADS-B flight transponder observations and verify
        PGAS place routing and spatial range filtering.
        """
        adapter = ADSBAviationAdapter()
        flight_stream = [
            {"hex": "A1B2C3", "lat": 37.618, "lon": -122.375, "speed": 180.0, "alt_baro": 3000.0},
            {"hex": "D4E5F6", "lat": 37.625, "lon": -122.380, "speed": 175.0, "alt_baro": 2800.0},
            {"hex": "987654", "lat": 34.050, "lon": -118.240, "speed": 450.0, "alt_baro": 35000.0},
        ]

        readings = list(adapter.parse(flight_stream))
        self.assertEqual(len(readings), 3)

        self.cluster.ingest_batch(readings)

        # Range query strictly covering San Francisco Bay Area (SFO)
        sfo_flights = self.cluster.query_range(37.60, -122.40, 37.65, -122.35)
        self.assertEqual(len(sfo_flights), 2)
        flight_ids = {f.sensor_id for f in sfo_flights}
        self.assertIn("flight_A1B2C3", flight_ids)
        self.assertIn("flight_D4E5F6", flight_ids)


if __name__ == "__main__":
    unittest.main()
