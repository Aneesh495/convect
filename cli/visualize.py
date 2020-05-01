"""
convect.cli.visualize - Terminal-based spatial heatmaps, sparklines, and tile distribution.

Provides ASCII and ANSI terminal visualization tools for spatiotemporal sensor distributions,
spatial anomaly locations, and X10 Place tile partitions without external graphical dependencies.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import math
from typing import Dict, List, Sequence, Tuple


class TerminalVisualizer:
    """
    Renders terminal graphics including 2D spatial heatmaps and time-series sparklines.
    """

    # Unicode block characters in ascending visual density
    SHADE_BLOCKS = [" ", "░", "▒", "▓", "█"]
    SPARKLINE_TICKS = [" ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    @classmethod
    def render_sparkline(cls, series: Sequence[float], width: int = 40) -> str:
        """
        Render a 1D numeric series as an inline sparkline.
        """
        if not series:
            return ""

        # Subsample or aggregate if series longer than width
        if len(series) > width:
            chunk_size = len(series) / width
            condensed = []
            for i in range(width):
                sub = series[int(i * chunk_size) : int((i + 1) * chunk_size)]
                condensed.append(sum(sub) / len(sub) if sub else 0.0)
            vals = condensed
        else:
            vals = list(series)

        min_v = min(vals)
        max_v = max(vals)
        rng = max_v - min_v

        out = []
        for v in vals:
            if rng <= 1e-9:
                idx = len(cls.SPARKLINE_TICKS) // 2
            else:
                ratio = (v - min_v) / rng
                idx = int(ratio * (len(cls.SPARKLINE_TICKS) - 1))
                idx = max(0, min(len(cls.SPARKLINE_TICKS) - 1, idx))
            out.append(cls.SPARKLINE_TICKS[idx])

        return "".join(out)

    @classmethod
    def render_spatial_density_map(
        cls,
        points: Sequence[Tuple[float, float]],
        min_lat: float,
        min_lon: float,
        max_lat: float,
        max_lon: float,
        width: int = 50,
        height: int = 20,
    ) -> str:
        """
        Renders a 2D spatial density grid using shaded block characters.
        """
        grid = [[0 for _ in range(width)] for _ in range(height)]

        lat_span = max(1e-6, max_lat - min_lat)
        lon_span = max(1e-6, max_lon - min_lon)

        for lat, lon in points:
            if min_lat <= lat <= max_lat and min_lon <= lon <= max_lon:
                # Row 0 is at max_lat (top of map)
                r = int(((max_lat - lat) / lat_span) * (height - 1))
                c = int(((lon - min_lon) / lon_span) * (width - 1))
                r = max(0, min(height - 1, r))
                c = max(0, min(width - 1, c))
                grid[r][c] += 1

        # Determine max cell count
        max_cnt = max((max(row) for row in grid), default=0)

        lines = []
        top_border = f"+-- [{max_lat:+.2f}N] " + "-" * (width - 18) + f" [{max_lon:+.2f}E] +"
        lines.append(top_border)

        for r in range(height):
            row_chars = []
            for c in range(width):
                cnt = grid[r][c]
                if cnt == 0:
                    row_chars.append(" ")
                elif max_cnt <= 1:
                    row_chars.append(cls.SHADE_BLOCKS[2])
                else:
                    level = int((cnt / max_cnt) * (len(cls.SHADE_BLOCKS) - 1)) + 1
                    level = max(1, min(len(cls.SHADE_BLOCKS) - 1, level))
                    row_chars.append(cls.SHADE_BLOCKS[level])
            lines.append("| " + "".join(row_chars) + " |")

        bot_border = f"+-- [{min_lat:+.2f}S] " + "-" * (width - 18) + f" [{min_lon:+.2f}W] +"
        lines.append(bot_border)
        lines.append(f"  Total Indexed Points: {len(points)} | Max Cell Density: {max_cnt}")

        return "\n".join(lines)

    @classmethod
    def render_tile_partition_map(
        cls,
        tiles_by_place: Dict[int, List[Tuple[float, float, float, float]]],
        width: int = 50,
        height: int = 20,
    ) -> str:
        """
        Renders tile spatial ownership across X10 Places using Place ID numeric markers.
        """
        # Determine global extent
        all_boxes = [box for boxes in tiles_by_place.values() for box in boxes]
        if not all_boxes:
            return "No tile partitions registered."

        min_lat = min(b[0] for b in all_boxes)
        min_lon = min(b[1] for b in all_boxes)
        max_lat = max(b[2] for b in all_boxes)
        max_lon = max(b[3] for b in all_boxes)

        grid = [["." for _ in range(width)] for _ in range(height)]
        lat_span = max(1e-6, max_lat - min_lat)
        lon_span = max(1e-6, max_lon - min_lon)

        for place_id, boxes in sorted(tiles_by_place.items()):
            marker = str(place_id % 10)
            for (blat0, blon0, blat1, blon1) in boxes:
                r0 = int(((max_lat - blat1) / lat_span) * (height - 1))
                r1 = int(((max_lat - blat0) / lat_span) * (height - 1))
                c0 = int(((blon0 - min_lon) / lon_span) * (width - 1))
                c1 = int(((blon1 - min_lon) / lon_span) * (width - 1))

                r0 = max(0, min(height - 1, r0))
                r1 = max(0, min(height - 1, r1))
                c0 = max(0, min(width - 1, c0))
                c1 = max(0, min(width - 1, c1))

                for r in range(min(r0, r1), max(r0, r1) + 1):
                    for c in range(min(c0, c1), max(c0, c1) + 1):
                        grid[r][c] = marker

        lines = ["+-- X10 Place Spatial Partition Map " + "-" * (width - 27) + "+"]
        for r in range(height):
            lines.append("| " + "".join(grid[r]) + " |")
        lines.append("+-" + "-" * width + "-+")
        lines.append(f"  Places: {sorted(tiles_by_place.keys())} | Total Tiles: {len(all_boxes)}")
        return "\n".join(lines)
