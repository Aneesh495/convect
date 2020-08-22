# Convect System Design Specification

## 1. System Architecture

```mermaid
flowchart TD
    subgraph Ingestion Layer [Python Ingestion Layer]
        S1[GeoJSON Streams] --> AD[Format Adapters]
        S2[CSV Feeds] --> AD
        S3[NOAA ISD Records] --> AD
        S4[Synthetic Generator] --> AD
        AD --> Proto[Binary Protocol Encoder]
        Proto --> Client[TCP Ingest Client]
    end

    subgraph Cluster [X10 PGAS Engine Cluster]
        Client --> Net[IngestServer Place 0]
        Net --> Router[TileRouter]
        
        Router -. at(P0) async .-> P0[Place 0: Northern Tiles]
        Router -. at(P1) async .-> P1[Place 1: Western Tiles]
        Router -. at(P2) async .-> P2[Place 2: Eastern Tiles]
        Router -. at(P3) async .-> P3[Place 3: Southern Tiles]

        subgraph Worker [Per-Place Processing Engine]
            WAL[Write-Ahead Log]
            Watermark[Event Watermark]
            RTree[Native C R*-Tree Index]
            Window[Sliding Time Window]
            LOF[Local Outlier Factor]
            CUSUM[Temporal CUSUM]
            Snap[Snapshot Manager]
        end
    end

    subgraph Query [Distributed Query Engine]
        CLI[Convect CLI] --> Planner[SpatialQueryPlan]
        Planner --> Exec[QueryExecutor]
        Exec ==> P0
        Exec ==> P1
        Exec ==> P2
        Exec ==> P3
    end
```

## 2. Ingestion Wire Framing Specification

Every message sent across the ingestion socket is wrapped in a self-describing binary frame:

```
+--------+--------+--------+--------+----------+---------+
| Magic  | Ver    | Type   | Length | Payload  | CRC32   |
| 2B     | 1B     | 1B     | 4B     | variable | 4B      |
+--------+--------+--------+--------+----------+---------+
```

### Field Definitions:
- `Magic` (2 Bytes): `0xC0EC` (Big-Endian). Distinctive visual identifier for wire inspection.
- `Version` (1 Byte): `0x01`. Incremented on breaking payload schema revisions.
- `Type` (1 Byte):
  - `0x01`: `SENSOR_READING` (Single reading)
  - `0x02`: `BATCH_READINGS` (Repeated array of readings)
  - `0x03`: `HEARTBEAT` (Cluster health keepalive)
  - `0x04`: `CONTROL` (Administrative commands)
- `Length` (4 Bytes): Unsigned 32-bit integer specifying payload size in bytes.
- `Payload` (Variable): Type-specific binary layout.
- `CRC32` (4 Bytes): IEEE 802.3 32-bit CRC computed across `Magic`, `Ver`, `Type`, `Length`, and `Payload`. Frames failing checksum verification are immediately rejected without buffer corruption.

## 3. Distributed Query Execution Sequence

```mermaid
sequenceDiagram
    autonumber
    actor User as User / CLI
    participant QP as QueryExecutor
    participant P0 as Place 0
    participant P1 as Place 1
    participant P2 as Place 2
    participant P3 as Place 3

    User->>QP: executeRangeQuery(bbox)
    QP->>QP: Decompose bbox into target Place list
    
    rect rgb(240, 248, 255)
        note right of QP: Parallel Execution via X10 finish / at
        par Place 0 Query
            QP->>P0: at(P0) async queryLocalRtree(bbox)
            P0-->>QP: Subtree Matches [readings...]
        and Place 1 Query
            QP->>P1: at(P1) async queryLocalRtree(bbox)
            P1-->>QP: Subtree Matches [readings...]
        and Place 2 Query
            QP->>P2: at(P2) async queryLocalRtree(bbox)
            P2-->>QP: Subtree Matches [readings...]
        end
    end
    
    QP->>QP: Consolidate & sort results by timestamp
    QP-->>User: Consolidated Spatial Results
```

## 4. Fault Tolerance and State Recovery

Each X10 Place maintains two independent recovery mechanisms:
1. **Write-Ahead Log (WAL)**: All incoming sensor readings are written sequentially to an append-only log prior to indexing in the in-memory R*-tree or memory buffers.
2. **Periodic Snapshots**: The `SnapshotManager` periodically captures a checkpoint of the spatial index and sliding window accumulators, recording the latest sequence number $S_{snap}$.
3. **Recovery Sequence**: When a Place experiences hardware termination, the `FailoverCoordinator` reassigns its Hilbert partition to a healthy surviving peer. The recovering node initializes state from snapshot $S_{snap}$ and replays log entries from $S_{snap} + 1$ to the log tail, achieving exact state recovery.
