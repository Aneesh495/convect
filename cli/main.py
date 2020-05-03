"""
convect.cli.main - Command-line interface for the Convect distributed geospatial engine.

Subcommands:
  ingest   - Ingest data from CSV, GeoJSON, or NOAA ISD sources into the engine
  generate - Generate synthetic spatiotemporal sensor streams with anomalies
  query    - Query spatial bounding boxes, radius circles, or k-NN from the engine
  status   - View X10 Place topology, tile partitions, and watermarks
  bench    - Measure ingestion and spatial indexing throughput
  map      - Render terminal-based spatial density heatmaps

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from typing import List, Tuple

from cli.formatter import TableFormatter, SummaryStats
from cli.visualize import TerminalVisualizer
from ingest.adapters import CSVAdapter, GeoJSONAdapter, NOAAIsdAdapter
from ingest.client import ConvectIngestClient
from ingest.generators import GridGenerator, ClusterGenerator, RandomWalkGenerator, AnomalyInjector


def cmd_generate(args: argparse.Namespace) -> int:
    """Generate synthetic sensor streams."""
    if args.pattern == "grid":
        gen = GridGenerator(
            min_lat=args.min_lat,
            min_lon=args.min_lon,
            max_lat=args.max_lat,
            max_lon=args.max_lon,
            rows=args.grid_rows,
            cols=args.grid_cols,
            metric=args.metric,
        )
        stream = gen.generate(steps=args.steps, interval_sec=args.interval)
    elif args.pattern == "cluster":
        centers = [(args.min_lat + 0.1, args.min_lon + 0.1), (args.max_lat - 0.1, args.max_lon - 0.1)]
        gen = ClusterGenerator(centers=centers, sensors_per_cluster=args.sensors // 2, metric=args.metric)
        stream = gen.generate(steps=args.steps, interval_sec=args.interval)
    else:
        gen = RandomWalkGenerator(num_sensors=args.sensors, start_lat=args.min_lat, start_lon=args.min_lon, metric=args.metric)
        stream = gen.generate(steps=args.steps, interval_sec=args.interval)

    if args.inject_anomalies:
        injector = AnomalyInjector(point_anomaly_prob=0.05)
        stream = injector.wrap(stream)

    count = 0
    out_fp = open(args.output, "w", encoding="utf-8") if args.output else sys.stdout
    try:
        if args.format == "csv":
            out_fp.write("sensor_id,latitude,longitude,timestamp,metric,value,quality\n")
            for r in stream:
                out_fp.write(f"{r.sensor_id},{r.latitude:.6f},{r.longitude:.6f},{r.timestamp},{r.metric},{r.value:.2f},{r.quality}\n")
                count += 1
        else:
            for r in stream:
                feat = {
                    "type": "Feature",
                    "geometry": {"type": "Point", "coordinates": [r.longitude, r.latitude]},
                    "properties": {
                        "sensor_id": r.sensor_id,
                        "timestamp": r.timestamp,
                        "metric": r.metric,
                        "value": r.value,
                        "quality": r.quality,
                    },
                }
                out_fp.write(json.dumps(feat) + "\n")
                count += 1
    finally:
        if args.output:
            out_fp.close()

    sys.stderr.write(f"Generated {count} sensor readings ({args.pattern} pattern).\n")
    return 0


def cmd_ingest(args: argparse.Namespace) -> int:
    """Ingest readings into engine or execute dry run."""
    if args.format == "csv":
        adapter = CSVAdapter(default_metric=args.metric)
    elif args.format == "geojson":
        adapter = GeoJSONAdapter(default_metric=args.metric)
    elif args.format == "noaa":
        adapter = NOAAIsdAdapter(target_metric=args.metric)
    else:
        sys.stderr.write(f"Unsupported format: {args.format}\n")
        return 1

    stream = adapter.parse_file(args.source)

    if args.dry_run:
        rows = []
        for idx, r in enumerate(stream):
            if idx < 20:
                rows.append([r.sensor_id, f"{r.latitude:.4f}", f"{r.longitude:.4f}", r.timestamp, r.metric, r.value, r.quality])
            elif idx == 20:
                rows.append(["...", "...", "...", "...", "...", "...", "..."])
        stats = adapter.get_stats()
        print(TableFormatter.format_table(["Sensor ID", "Latitude", "Longitude", "Timestamp", "Metric", "Value", "Quality"], rows))
        print(f"\nDry Run Complete: {stats['valid']} valid readings, {stats['rejected']} rejected.")
        return 0

    client = ConvectIngestClient(host=args.host, port=args.port, batch_size=args.batch_size)
    client.connect()
    sent = 0
    try:
        for r in stream:
            client.send_reading(r)
            sent += 1
        client.flush()
    finally:
        client.close()

    stats = client.stats
    print(f"Ingestion Finished: Sent {stats.readings_sent} readings ({stats.bytes_sent} bytes) across {stats.batches_sent} batches.")
    return 0


def cmd_map(args: argparse.Namespace) -> int:
    """Render terminal spatial heatmap from input data."""
    if args.format == "csv":
        adapter = CSVAdapter()
    else:
        adapter = GeoJSONAdapter()

    points = [(r.latitude, r.longitude) for r in adapter.parse_file(args.source)]
    if not points:
        print("No valid points found in input source.")
        return 1

    min_lat = min(p[0] for p in points)
    max_lat = max(p[0] for p in points)
    min_lon = min(p[1] for p in points)
    max_lon = max(p[1] for p in points)

    heatmap = TerminalVisualizer.render_spatial_density_map(
        points, min_lat, min_lon, max_lat, max_lon, width=args.width, height=args.height
    )
    print(heatmap)
    return 0


def cmd_bench(args: argparse.Namespace) -> int:
    """Measure ingestion client and parsing throughput."""
    print("Running Convect Ingestion Benchmark...")
    gen = GridGenerator(min_lat=30.0, min_lon=-120.0, max_lat=40.0, max_lon=-110.0, rows=20, cols=20)

    t0 = time.perf_counter()
    readings = list(gen.generate(steps=args.steps))
    t1 = time.perf_counter()

    gen_rate = len(readings) / max(1e-6, t1 - t0)
    print(f"Generated {len(readings)} synthetic readings in {t1 - t0:.3f}s ({gen_rate:,.0f} readings/sec)")

    # Serialize benchmark
    from ingest.protocol import ConvectProtocol
    t2 = time.perf_counter()
    batches = []
    batch_sz = 100
    for i in range(0, len(readings), batch_sz):
        b = readings[i : i + batch_sz]
        batches.append(ConvectProtocol.serialize_batch(b))
    t3 = time.perf_counter()

    ser_rate = len(readings) / max(1e-6, t3 - t2)
    print(f"Serialized {len(batches)} binary batches in {t3 - t2:.3f}s ({ser_rate:,.0f} readings/sec)")

    # Summary table
    table = TableFormatter.format_table(
        ["Benchmark Phase", "Count", "Elapsed (s)", "Throughput (ops/sec)"],
        [
            ["Generation", len(readings), f"{t1 - t0:.3f}", f"{gen_rate:,.0f}"],
            ["Binary Framing", len(readings), f"{t3 - t2:.3f}", f"{ser_rate:,.0f}"],
        ],
    )
    print("\n" + table)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="convect",
        description="Convect: Distributed Geospatial Stream Processing Engine CLI",
    )
    sub = parser.add_subparsers(dest="subcommand", required=True)

    # generate
    p_gen = sub.add_parser("generate", help="Generate synthetic spatiotemporal sensor streams")
    p_gen.add_argument("--pattern", choices=["grid", "cluster", "walk"], default="grid")
    p_gen.add_argument("--min-lat", type=float, default=37.0)
    p_gen.add_argument("--min-lon", type=float, default=-122.5)
    p_gen.add_argument("--max-lat", type=float, default=38.0)
    p_gen.add_argument("--max-lon", type=float, default=-121.5)
    p_gen.add_argument("--grid-rows", type=int, default=10)
    p_gen.add_argument("--grid-cols", type=int, default=10)
    p_gen.add_argument("--sensors", type=int, default=50)
    p_gen.add_argument("--steps", type=int, default=20)
    p_gen.add_argument("--interval", type=float, default=1.0)
    p_gen.add_argument("--metric", default="temperature")
    p_gen.add_argument("--inject-anomalies", action="store_true")
    p_gen.add_argument("--format", choices=["csv", "geojson"], default="csv")
    p_gen.add_argument("--output", "-o", default=None)

    # ingest
    p_ing = sub.add_parser("ingest", help="Ingest observations from source files into engine")
    p_ing.add_argument("source", help="Path to input data file (CSV, GeoJSON, NOAA ISD)")
    p_ing.add_argument("--format", choices=["csv", "geojson", "noaa"], default="csv")
    p_ing.add_argument("--metric", default="temperature")
    p_ing.add_argument("--host", default="127.0.0.1")
    p_ing.add_argument("--port", type=int, default=9100)
    p_ing.add_argument("--batch-size", type=int, default=100)
    p_ing.add_argument("--dry-run", action="store_true")

    # map
    p_map = sub.add_parser("map", help="Render terminal spatial density heatmap")
    p_map.add_argument("source", help="Path to sensor data file")
    p_map.add_argument("--format", choices=["csv", "geojson"], default="csv")
    p_map.add_argument("--width", type=int, default=50)
    p_map.add_argument("--height", type=int, default=18)

    # bench
    p_bnc = sub.add_parser("bench", help="Measure local ingestion and serialization throughput")
    p_bnc.add_argument("--steps", type=int, default=25)

    args = parser.parse_args()

    if args.subcommand == "generate":
        return cmd_generate(args)
    elif args.subcommand == "ingest":
        return cmd_ingest(args)
    elif args.subcommand == "map":
        return cmd_map(args)
    elif args.subcommand == "bench":
        return cmd_bench(args)

    return 0


if __name__ == "__main__":
    sys.exit(main())
