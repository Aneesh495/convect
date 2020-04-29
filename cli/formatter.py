"""
convect.cli.formatter - High-density tabular, JSON, and summary output formatters.

Formats query results, anomaly detections, and engine telemetry for human inspection
in terminals or machine ingestion via stdout.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import json
import math
from typing import Any, Dict, List, Sequence, Union


class TableFormatter:
    """
    Renders structured rows as clean ASCII / Unicode box-drawing tables.
    """

    @staticmethod
    def format_table(headers: Sequence[str], rows: Sequence[Sequence[Any]]) -> str:
        """Render tabular data with aligned borders."""
        if not headers and not rows:
            return ""

        str_headers = [str(h) for h in headers]
        str_rows = [[str(cell) for cell in row] for row in rows]

        # Calculate max column widths
        num_cols = len(str_headers)
        col_widths = [len(h) for h in str_headers]

        for row in str_rows:
            for idx in range(min(num_cols, len(row))):
                col_widths[idx] = max(col_widths[idx], len(row[idx]))

        # Build border lines
        sep_top = "+-" + "-+-".join("-" * w for w in col_widths) + "-+"
        sep_mid = "+=" + "=+=".join("=" * w for w in col_widths) + "=+"
        sep_bot = "+-" + "-+-".join("-" * w for w in col_widths) + "-+"

        # Header row
        header_line = "| " + " | ".join(h.ljust(col_widths[i]) for i, h in enumerate(str_headers)) + " |"

        lines = [sep_top, header_line, sep_mid]

        for row in str_rows:
            padded_cells = []
            for i in range(num_cols):
                val = row[i] if i < len(row) else ""
                # Right-align if numeric, else left-align
                is_num = False
                try:
                    float(val)
                    is_num = True
                except ValueError:
                    pass

                if is_num:
                    padded_cells.append(val.rjust(col_widths[i]))
                else:
                    padded_cells.append(val.ljust(col_widths[i]))

            lines.append("| " + " | ".join(padded_cells) + " |")

        lines.append(sep_bot)
        return "\n".join(lines)


class SummaryStats:
    """
    Calculates summary statistics (mean, stddev, percentiles) for numeric series.
    """

    @staticmethod
    def compute(values: Sequence[float]) -> Dict[str, float]:
        if not values:
            return {"count": 0, "mean": 0.0, "stddev": 0.0, "min": 0.0, "max": 0.0, "p50": 0.0, "p95": 0.0}

        sorted_vals = sorted(values)
        n = len(sorted_vals)
        mean_v = sum(sorted_vals) / n
        variance = sum((x - mean_v) ** 2 for x in sorted_vals) / max(1, n - 1)
        stddev_v = math.sqrt(variance)

        def percentile(p: float) -> float:
            k = (n - 1) * p
            f = math.floor(k)
            c = math.ceil(k)
            if f == c:
                return sorted_vals[int(k)]
            return sorted_vals[int(f)] * (c - k) + sorted_vals[int(c)] * (k - f)

        return {
            "count": float(n),
            "mean": round(mean_v, 3),
            "stddev": round(stddev_v, 3),
            "min": round(sorted_vals[0], 3),
            "max": round(sorted_vals[-1], 3),
            "p50": round(percentile(0.50), 3),
            "p95": round(percentile(0.95), 3),
            "p99": round(percentile(0.99), 3),
        }
