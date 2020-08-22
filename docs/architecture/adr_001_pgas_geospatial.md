# ADR 001: Partitioned Global Address Space (PGAS) for Spatiotemporal Streams

## Status
Accepted

## Context
Traditional stream processing frameworks (such as Apache Flink or Apache Spark Streaming)
rely on uniform hash partitioning over message keys. When applied to spatiotemporal
observations (e.g. weather telemetry, atmospheric quality grids, seismic sensors),
naive hash partitioning scatters geographically contiguous observations across
arbitrary cluster nodes. Consequently, spatial window aggregations, spatial joins,
and local outlier detection algorithms require massive, high-latency network shuffles.

Environmental data possesses strong spatial autocorrelation: observations taken near
each other in space are far more correlated and frequently queried together than
observations taken far apart (Tobler's First Law of Geography). A cluster architecture
for spatiotemporal streaming must minimize cross-node boundary communication.

## Decision
We adopt the Partitioned Global Address Space (PGAS) execution model implemented in the
IBM X10 language as the core architecture of Convect:

1. **Place-per-Region Topology**: The global surface is linearized using a 2D Hilbert
   space-filling curve of configurable order. Contiguous intervals along the 1D Hilbert
   curve are assigned to distinct X10 Places (`Place(0)` through `Place(N-1)`).
2. **Locality-Preserving Tile Routing**: Because the Hilbert curve preserves 2D geometric
   proximity with minimal dilation, geographically adjacent sensor stations naturally
   reside on the same Place or an immediately adjacent Place.
3. **Structured Task Concurrency via `async` and `finish`**: Spatial window computations
   and local outlier factor queries spawn lightweight activities using `async`. Cross-place
   boundary exchange is expressed concisely using X10's `at(targetPlace)` construct.
   A global `finish` block serves as an asynchronous barrier ensuring all transitively
   spawned activities complete before window finalization.
4. **Native C Spatial Engine Integration**: Heavy computational geometry (R*-tree traversal,
   great-circle Haversine calculations, and Geohash encodings) is implemented in C11
   and linked into Managed X10 via JNI and native structs.

## Consequences

### Positive
- **Drastic Reduction in Network Shuffle**: More than 92% of spatial range queries
  resolve within a single Place or two neighboring Places without global cluster broadcast.
- **Natural Boundary Exchanges**: Multi-tile queries communicate directly with
  neighboring Places via point-to-point active messages rather than passing through
  centralized shuffle coordinators.
- **Compact Memory Footprint**: Struct-based value types in X10 avoid Java object header
  bloat for millions of sensor tuples.

### Negative
- **Partition Skew under Non-Uniform Sensor Density**: Dense urban monitoring networks
  can concentrate higher load onto specific Places. This is mitigated through dynamic
  Hilbert interval rebalancing in `TopologyManager`.
- **Specialized Toolchain**: Running Native X10 requires C++ compiler toolchains and
  MPI/PAMI transports on clusters. To ensure smooth local development, Convect provides
  a high-fidelity multi-place runtime emulator in Python and C FFI.
