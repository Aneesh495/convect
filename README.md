# convect

A distributed geospatial stream processing engine that partitions sensor feeds
across places, detects spatial anomalies in real time, and answers continuous
queries over environmental data.

## Overview

convect is purpose-built for spatiotemporal data processing. It ingests continuous
streams of georeferenced sensor readings (weather stations, air quality monitors,
seismic sensors, ocean buoys), distributes computation across a cluster of places
using X10's Partitioned Global Address Space model, and surfaces anomalies and
patterns as they emerge.

The system is not a generic stream processor. Every design decision, from the
spatial partitioning scheme to the query execution model, is tuned for data that
has both a location and a timestamp.

## Architecture

```
                    +------------------+
                    |   Sensor Feeds   |
                    | (CSV, GeoJSON,   |
                    |  Simulated)      |
                    +--------+---------+
                             |
                    +--------v---------+
                    |  Ingest Layer    |
                    |  (Python)        |
                    +--------+---------+
                             |
              +--------------v--------------+
              |      X10 Engine Core        |
              |                             |
              |  +--------+  +-----------+  |
              |  | Router |  | Watermark |  |
              |  +---+----+  | Clock     |  |
              |      |       +-----------+  |
              |  +---v----+                 |
              |  | Tile   |  +-----------+  |
              |  | Owner  |  | Anomaly   |  |
              |  | Place0 |  | Detector  |  |
              |  +--------+  +-----------+  |
              |  +--------+                 |
              |  | Tile   |  +-----------+  |
              |  | Owner  |  | Query     |  |
              |  | Place1 |  | Executor  |  |
              |  +--------+  +-----------+  |
              |      ...                    |
              +--------------+--------------+
                             |
                    +--------v---------+
                    |  Spatial Index   |
                    |  (C via JNI)     |
                    |  R-tree, Quad,   |
                    |  Geohash, Hilbert|
                    +------------------+
```

### Components

**Core Engine (X10)** -- The distributed processing kernel. Each Place owns a
set of geographic tiles and processes sensor readings that fall within its
boundaries. Places communicate via X10's `at` construct for cross-tile queries,
boundary event propagation, and anomaly correlation. The engine handles
temporal ordering through watermarks, manages windowed aggregations, and
coordinates distributed spatial joins.

**Spatial Index (C)** -- High-performance spatial data structures accessible
from X10 through a JNI bridge. Includes an R-tree with Sort-Tile-Recursive
bulk loading, a geohash encoder for O(1) tile lookups, a quadtree for
adaptive-resolution queries, and Hilbert curve linearization for
locality-preserving partitioning.

**Ingest Layer (Python)** -- Adapters for common sensor data formats (GeoJSON
features, CSV time series, custom binary protocols) and synthetic data
generators for testing. Feeds data into the X10 engine through a socket-based
ingestion protocol.

**CLI and Visualization (Python)** -- Command-line interface for querying the
running engine, inspecting tile state, and rendering spatial heatmaps of
sensor coverage and detected anomalies.

## Key Concepts

### Spatial Partitioning with Hilbert Curves

Sensor data is assigned to tiles using a Hilbert space-filling curve. This
preserves spatial locality better than naive grid partitioning: points that
are geographically close tend to land on the same or neighboring tiles, which
minimizes cross-Place communication for spatial queries.

### Watermark-based Temporal Ordering

Each Place maintains a low watermark tracking the oldest unprocessed event.
Late-arriving data is buffered in side inputs and triggers window
recomputation. This guarantees eventually-correct results even when sensors
report out of order.

### Distributed Spatial Joins

Queries spanning multiple tiles execute a distributed sweep-line join
coordinated across Places. The query planner decomposes a bounding-box
query into per-tile subqueries, executes them in parallel with `finish`/`at`,
and merges the results.

### Anomaly Detection Pipeline

Multiple detection strategies run in parallel:

- **Spatial outlier**: Z-score deviation from spatial neighbors using a local
  outlier factor variant
- **Temporal changepoint**: CUSUM and PELT algorithms for abrupt shifts in
  time series
- **Spatial autocorrelation**: Moran's I statistic to detect breakdown of
  expected spatial patterns
- **Multi-variate correlation**: Detects when historically correlated sensors
  diverge

### Write-Ahead Log Recovery

Each Place writes sensor readings and computed state to a write-ahead log.
On failure, a replacement Place replays the log from the last checkpoint to
recover state without data loss.

## Building

### Prerequisites

- **X10** (2.6.2+): [github.com/x10-lang/x10](https://github.com/x10-lang/x10)
  with the Managed X10 (Java) backend
- **JDK 8**: Required by the X10 compiler
- **GCC/Clang**: C11 compiler for the spatial index
- **Python 3.10+**: For the ingest layer and CLI
- **Apache Ant 1.10+**: For building X10 from source (if needed)

### Quick Start

```bash
# Clone the repo
git clone https://github.com/Aneesh495/convect.git
cd convect

# Build the C spatial index
cd index && make && cd ..

# Build the JNI bridge
cd bridge && make && cd ..

# Compile the X10 engine (Managed X10 / Java backend)
x10c -sourcepath core -d build/classes core/engine/ConvectEngine.x10

# Set up the Python environment
cd ingest && python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt && cd ..

# Run with synthetic data (4 places)
X10_NPLACES=4 x10 -classpath build/classes convect.core.engine.ConvectEngine \
    --ingest-port 9100 --tile-order 6
```

### Docker (Recommended)

```bash
docker build -t convect .
docker run -it --rm -p 9100:9100 convect --tile-order 6 --places 4
```

### Running Tests

```bash
# X10 unit tests
make test-x10

# C unit tests
cd index && make test && cd ..

# Python tests
cd ingest && python3 -m pytest ../tests/python/ -v && cd ..

# Integration tests
make test-integration
```

## Project Structure

```
convect/
  core/                 X10 source: the distributed processing engine
    types/              Core data types (SensorReading, GeoPoint, Tile, etc.)
    engine/             Stream ingestion, partitioning, and routing
    compute/            Spatial operators (interpolation, density, hotspots)
    detect/             Anomaly detection (statistical, spatial, temporal)
    query/              Distributed query planning and execution
    clock/              Watermark management and windowing
    topology/           Place topology, tile ownership, rebalancing
    net/                Inter-place messaging protocol
    storage/            Write-ahead log, snapshots, checkpointing
    fault/              Failure detection, state migration, recovery
  index/                C source: high-performance spatial indexing
    rtree/              R-tree with STR bulk loading
    geohash/            Geohash encoding/decoding and neighbor lookup
    quadtree/           Quadtree for adaptive spatial resolution
    hilbert/            Hilbert curve linearization
  bridge/               C source: JNI bridge between X10 and C index
  ingest/               Python: data source adapters and generators
    adapters/           GeoJSON, CSV, binary protocol adapters
    generators/         Synthetic sensor data generators
  cli/                  Python: command-line query interface
  tests/                Test suites for all components
    x10/                X10 unit and structure tests
    c/                  C unit tests
    python/             Python unit tests
    integration/        Cross-component integration tests
  docs/                 Developer documentation
    architecture/       Architecture decision records and diagrams
    api/                API reference
  bench/                Performance benchmarks
```

## Technical Details

For in-depth documentation on the system architecture, data flow, and design
decisions, see [docs/architecture/](docs/architecture/).

## License

MIT
