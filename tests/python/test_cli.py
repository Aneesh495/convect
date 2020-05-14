"""
tests.python.test_cli - Unit tests for CLI components, formatters, and terminal visualizers.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

import unittest
from cli.formatter import TableFormatter, SummaryStats
from cli.visualize import TerminalVisualizer
from cli.main import main


class TestCli(unittest.TestCase):

    def test_table_formatter(self) -> None:
        headers = ["Sensor ID", "Latitude", "Longitude", "Temp (C)"]
        rows = [
            ["alpha_01", "37.7749", "-122.4194", "18.5"],
            ["beta_02", "34.0522", "-118.2437", "22.1"],
        ]
        table = TableFormatter.format_table(headers, rows)
        self.assertIn("Sensor ID", table)
        self.assertIn("alpha_01", table)
        self.assertIn("+=", table)
        self.assertIn("+-", table)

    def test_summary_stats(self) -> None:
        vals = [10.0, 20.0, 30.0, 40.0, 50.0]
        stats = SummaryStats.compute(vals)
        self.assertEqual(stats["count"], 5)
        self.assertAlmostEqual(stats["mean"], 30.0)
        self.assertAlmostEqual(stats["min"], 10.0)
        self.assertAlmostEqual(stats["max"], 50.0)
        self.assertAlmostEqual(stats["p50"], 30.0)

    def test_sparkline_renderer(self) -> None:
        series = [1.0, 2.0, 3.0, 4.0, 5.0, 8.0, 4.0, 2.0]
        spark = TerminalVisualizer.render_sparkline(series, width=10)
        self.assertEqual(len(spark), len(series))
        self.assertTrue(any(c in spark for c in TerminalVisualizer.SPARKLINE_TICKS))

    def test_spatial_density_map_renderer(self) -> None:
        points = [
            (37.5, -122.5), (37.5, -122.5), (37.8, -122.2),
            (37.1, -122.8), (37.9, -122.1),
        ]
        grid_map = TerminalVisualizer.render_spatial_density_map(
            points, min_lat=37.0, min_lon=-123.0, max_lat=38.0, max_lon=-122.0,
            width=20, height=8
        )
        self.assertIn("[+38.00N]", grid_map)
        self.assertIn("[+37.00S]", grid_map)
        self.assertIn("Total Indexed Points: 5", grid_map)

    def test_tile_partition_map_renderer(self) -> None:
        tiles = {
            0: [(37.0, -123.0, 37.5, -122.5)],
            1: [(37.5, -123.0, 38.0, -122.5)],
            2: [(37.0, -122.5, 37.5, -122.0)],
            3: [(37.5, -122.5, 38.0, -122.0)],
        }
        part_map = TerminalVisualizer.render_tile_partition_map(tiles, width=20, height=8)
        self.assertIn("Place Spatial Partition Map", part_map)
        self.assertIn("Places: [0, 1, 2, 3]", part_map)


if __name__ == "__main__":
    unittest.main()
