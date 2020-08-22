"""
convect.bench.benchmark_throughput - End-to-end stream ingestion and routing throughput.

Evaluates:
  - Generation rate across thousands of synthetic stations
  - Binary protocol serialization and CRC32 throughput
  - Multi-place distributed PGAS cluster routing throughput
  - Range query latency over memory-resident sensor windows

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import os
import sys
import time

# Ensure repository root is on sys.path
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from cli.formatter import TableFormatter
from core.runtime.X10RuntimeEmulator import X10RuntimeCluster
from ingest.generators import GridGenerator
from ingest.protocol import ConvectProtocol


def run_benchmark() -> None:
    print("==============================================================")
    print(" Convect End-to-End Stream Ingestion & Routing Benchmark      ")
    print("==============================================================\n")

    # 1. Generate 50,000 readings
    num_sensors = 500
    steps = 100
    total_target = num_sensors * steps
    print(f"[1/4] Generating {total_target:,} synthetic observations ({num_sensors} stations, {steps} steps)...")

    gen = GridGenerator(min_lat=32.0, min_lon=-122.0, max_lat=42.0, max_lon=-112.0, rows=25, cols=20)
    t0 = time.perf_counter()
    readings = list(gen.generate(steps=steps))
    t1 = time.perf_counter()
    gen_rate = len(readings) / max(1e-6, t1 - t0)
    print(f"      -> Generated {len(readings):,} readings in {t1 - t0:.3f} s ({gen_rate:,.0f} readings/sec)\n")

    # 2. Wire framing benchmark
    print(f"[2/4] Binary protocol batch serialization (100 readings/batch)...")
    batch_size = 100
    t2 = time.perf_counter()
    batches = []
    for i in range(0, len(readings), batch_size):
        b = readings[i : i + batch_size]
        batches.append(ConvectProtocol.serialize_batch(b))
    t3 = time.perf_counter()
    ser_rate = len(readings) / max(1e-6, t3 - t2)
    total_bytes = sum(len(b) for b in batches)
    mb_per_sec = (total_bytes / (1024 * 1024)) / max(1e-6, t3 - t2)
    print(f"      -> Serialized {len(batches):,} frames ({total_bytes / (1024*1024):.1f} MB) in {t3 - t2:.3f} s ({ser_rate:,.0f} msg/sec, {mb_per_sec:.1f} MB/s)\n")

    # 3. Multi-place routing benchmark
    print(f"[3/4] Ingesting & routing into 8-place X10 PGAS cluster...")
    cluster = X10RuntimeCluster(num_places=8, tile_order=8)
    t4 = time.perf_counter()
    cluster.ingest_batch(readings)
    t5 = time.perf_counter()
    route_rate = len(readings) / max(1e-6, t5 - t4)
    print(f"      -> Routed {len(readings):,} readings in {t5 - t4:.3f} s ({route_rate:,.0f} readings/sec)\n")

    # 4. Range query latency benchmark
    print(f"[4/4] Parallel multi-place range queries (500 iterations)...")
    num_queries = 500
    t6 = time.perf_counter()
    hits = 0
    for _ in range(num_queries):
        res = cluster.query_range(35.0, -120.0, 39.0, -115.0)
        hits += len(res)
    t7 = time.perf_counter()
    query_lat_us = ((t7 - t6) / num_queries) * 1e6
    print(f"      -> {num_queries} parallel range queries in {t7 - t6:.3f} s ({query_lat_us:.1f} us/query, {hits:,} hits)\n")

    table = TableFormatter.format_table(
        ["Pipeline Stage", "Scale", "Elapsed (s)", "Throughput"],
        [
            ["Stream Generation", f"{len(readings):,} items", f"{t1 - t0:.3f}", f"{gen_rate:,.0f} items/s"],
            ["Binary Wire Serialization", f"{len(batches):,} batches", f"{t3 - t2:.3f}", f"{mb_per_sec:.1f} MB/s"],
            ["PGAS Place Routing", f"8 Places ({len(readings):,})", f"{t5 - t4:.3f}", f"{route_rate:,.0f} items/s"],
            ["Parallel Range Query", f"{num_queries} queries", f"{t7 - t6:.3f}", f"{query_lat_us:.1f} us/query"],
        ],
    )
    print(table)


if __name__ == "__main__":
    run_benchmark()
