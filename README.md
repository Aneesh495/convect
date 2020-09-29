# convect

A high-performance distributed spatiotemporal stream engine built around X10's Partitioned Global Address Space (PGAS) model, with native C spatial acceleration, continuous finite-difference transport solvers, and real-time spatial anomaly detection.

## Overview

convect is purpose-built for continuous spatiotemporal computing. It ingests high-velocity streams of georeferenced sensor observations (meteorological stations, maritime AIS vessels, aviation ADS-B transponders, ocean buoys), distributes computation across a cluster of Places using X10's Partitioned Global Address Space model, and executes continuous spatial queries, advection-dispersion plume simulations, and spatial anomaly detection in real time.

Every design decision, from space-filling curve partitioning to discrete global grid systems, is engineered for data defined simultaneously by continuous spatial coordinates and event timestamps.

---

## Architecture

```
                    +-------------------------------------+
                    |            Sensor Feeds             |
                    | (CSV, GeoJSON, NetCDF, AIS, ADS-B)  |
                    +------------------+------------------+
                                       |
                    +------------------v------------------+
                    |          Streaming Ingest           |
                    |  (Framed CRC32 TCP Wire Protocol)   |
                    +------------------+------------------+
                                       |
        +------------------------------v------------------------------+
        |                 X10 PGAS Distributed Engine                 |
        |                                                             |
        |   +-------------------+              +------------------+   |
        |   |    Tile Router    |              | Dynamic Balancer |   |
        |   | (Order-24 Hilbert)|              | (Load Profiling) |   |
        |   +---------+---------+              +------------------+   |
        |             |                                               |
        |   +---------v---------+              +------------------+   |
        |   |   Place Topology  |              | Watermark Clock  |   |
        |   |   (Places 0..P-1) |              | (Out-of-Order)   |   |
        |   +----+----+----+----+              +------------------+   |
        |        |    |    |                                          |
        |  +-----v-+  |  +-v------+            +------------------+   |
        |  |Place 0|  |  |Place 3 |            | Consensus Raft   |   |
        |  | (WAL) |  |  | (WAL)  |            | (Cluster Epochs) |   |
        |  +---+---+  |  +----+---+            +------------------+   |
        |      |      |       |                                       |
        |  +---v------v-------v---+            +------------------+   |
        |  |   Compute & Detect   |            | Continuous Query |   |
        |  |  Advection Solver    |            | Range & Radius   |   |
        |  |  Ordinary Kriging    |            | Spatial Join     |   |
        |  |  LOF & Moran's I LISA|            | Spatial DBSCAN   |   |
        |  +----------+-----------+            +------------------+   |
        +-------------|-----------------------------------------------+
                      |
        +-------------v-----------------------------------------------+
        |              Native C Spatial Acceleration                  |
        |                                                             |
        |   +-----------------------+     +-----------------------+   |
        |   |   R*-Tree & Quadtree  |     |   H3 Hexagonal DGGS   |   |
        |   | (STR Bulk / k-NN PQ)  |     | (Res 0..15 / k-Ring)  |   |
        |   +-----------------------+     +-----------------------+   |
        |   +-----------------------+     +-----------------------+   |
        |   |  Hilbert & Geohash    |     |  Spatial LSM MemTable |   |
        |   | (Decomposition BBox)  |     | (SkipList / Bloom)    |   |
        |   +-----------------------+     +-----------------------+   |
        +-------------------------------------------------------------+
```

---

## Core Capabilities

- **Partitioned Global Address Space (PGAS)**: Distributed spatiotemporal memory layout partitioning continuous coordinates across Places using order-24 Hilbert space-filling curves.
- **2D Finite-Difference Transport Solver**: Distributed upwind advection and central difference diffusion stencil solver with asynchronous PGAS halo boundary exchange.
- **Spatiotemporal Gaussian Processes & Kriging**: Ordinary Kriging spatial interpolation solving regularized covariance systems via Banachiewicz Cholesky decomposition.
- **Spatial Anomaly Detection**: Real-time statistical Outlier Factor (LOF), dual-accumulator CUSUM, Getis-Ord Gi* hot spot analysis, and Anselin Local Moran's I (LISA).
- **C11 Native Spatial Indexing**:
  - **R*-tree**: Overlap enlargement minimization, forced reinsertion (30%), margin-sum split axis selection, priority queue k-NN search, and STR bulk loading.
  - **Hexagonal DGGS (H3)**: Discrete global grid encoding, center decoding, parent rollups, and k-ring radial neighborhood expansion.
  - **Spatial LSM MemTable**: High-throughput SkipList write buffer keyed by compound `(Hilbert:48 | Timestamp:16)` with 3-hash Bloom filters.
  - **PR-Quadtree & Geohash**: Base32 and 64-bit integer geohashing with bounding box decomposition.
- **Multimodal Telemetry Adapters**:
  - Meteorological: NOAA Integrated Surface Database (ISD 3505) and NetCDF raster grids.
  - Maritime: Automatic Identification System (AIS) vessel telemetry.
  - Aviation: Automatic Dependent Surveillance - Broadcast (ADS-B) Mode-S transponders.
  - Generic: RFC 7946 GeoJSON and CSV formats with compression support.

---

## Benchmark Performance

Compiled under Clang `-O3 -std=c11` on Apple Silicon (M-series):

| Component / Benchmark | Metric | Measured Throughput / Latency |
|:---|:---|:---|
| **R*-Tree Bulk Loading** | 100,000 points (STR) | 0.61 seconds (~164,000 inserts/sec) |
| **R*-Tree Range Query** | 1,000 random bounding boxes | 0.047 ms per spatial query |
| **R*-Tree k-NN Search** | 1,000 nearest-neighbor searches | 0.137 ms per k-NN query |
| **Hilbert Projection** | Geographic coordinate to order-24 | 40,210,000 ops / sec |
| **Geohash Encoding** | Base32 64-bit binary encode | 6,432,000 ops / sec |
| **Stream Wire Serialization**| Binary CRC32 framing protocol | 75.8 MB / sec (single core) |
| **PGAS Place Routing** | Multi-place partition dispatcher | 258,000 readings / sec |

---

## Quickstart

### Prerequisites

- C11 compliant compiler (`clang` or `gcc`)
- Python 3.10+
- GNU Make

### Building and Testing

```bash
# Clone repository
git clone https://github.com/Aneesh495/convect.git
cd convect

# Compile C spatial libraries and run full test suites
make test
```

### Running Verification Suites

```bash
# Run C spatial index unit tests (340 assertions)
make test-c

# Run Python adapter and protocol unit tests
make test-python

# Run PGAS emulator and physical simulation tests
make test-integration

# Run performance benchmark suite
make bench
```

### CLI Inspection and Terminal Visualization

```bash
# Print summary statistics for synthetic stream
python3 cli/main.py stream --count 100 --generator cluster

# Render real-time terminal Unicode spatial density heatmap
python3 cli/main.py visualize --type density --count 500

# Inspect PGAS tile partition boundaries
python3 cli/main.py tiles --places 4 --order 8
```

---

## Repository Structure

```
convect/
  core/                 X10 distributed engine and PGAS runtime
    aggregate/          HyperLogLog spatial sketches and Welford aggregators
    clock/              Event watermarks and sliding time windows
    compute/            Advection-dispersion solver, Kriging, DBSCAN, KDE
    detect/             Local Outlier Factor, CUSUM, Moran's I LISA
    engine/             ConvectEngine cluster coordinator
    fault/              Heartbeat monitors and failover coordinators
    math/               Vector math, dense matrix ops, Cholesky decomposition
    net/                Wire protocol dispatchers and messaging
    query/              Spatial join executor, polygon ray-casting, query planner
    runtime/            Multi-place PGAS emulator with C FFI bindings
    storage/            Write-ahead logging (WAL) and snapshot managers
    topology/           Dynamic load balancer, tile router, Raft consensus
    types/              GeoPoint, BoundingBox, SensorReading, TileExtent
  index/                High-performance C11 spatial indexing engine
    geohash/            Geohash base32 encoding and 8-directional neighbors
    h3/                 Hexagonal discrete global grid system (H3)
    hilbert/            Hilbert curve projection and bounding box decomposition
    lsm/                Spatial LSM MemTable, SkipList, and Bloom filters
    quadtree/           PR-quadtree with adaptive subdivision
    rtree/              R*-tree with overlap minimization and STR bulk loader
  bridge/               JNI native bindings interfacing X10 and C
  ingest/               Streaming protocol, adapters, and data generators
    adapters/           CSV, GeoJSON, NOAA ISD, NetCDF, AIS, ADS-B
    generators/         Grid, cluster, random walk, and anomaly generators
    protocol.py         Binary framing format with CRC32 verification
  cli/                  Command-line dispatcher and terminal visualization
  tests/                Verification test suites
    c/                  Native C unit test suite (340 assertions)
    python/             Python protocol, adapter, and generator tests
    integration/        End-to-end PGAS and environmental simulation tests
    x10/                X10 algorithm and topology test suites
  docs/                 Technical specifications and architecture records
    architecture/       ADRs, spatial indexing theory, finite difference stencil
    api/                PGAS runtime specification and memory model
  bench/                Spatial indexing and stream throughput benchmarks
```

---

## Documentation

- [ADR 001: PGAS for Geospatial Stream Processing](docs/architecture/adr_001_pgas_geospatial.md)
- [Distributed Spatial Indexing & Space-Filling Curves](docs/architecture/distributed_spatial_indexing.md)
- [Finite-Difference Advection-Dispersion Stencil Solver](docs/architecture/advection_dispersion_stencil.md)
- [Spatiotemporal Gaussian Processes and Kriging](docs/architecture/spatiotemporal_kriging.md)
- [X10 PGAS Runtime and Memory Model Specification](docs/api/x10_pgas_specification.md)
- [System Architecture and Component Design](docs/architecture/convect_design_specification.md)

---

## License

Apache-2.0
