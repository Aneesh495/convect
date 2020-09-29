# Convect X10 PGAS Runtime and Memory Model Specification

## 1. Architectural Overview

Convect is structured around the Partitioned Global Address Space (PGAS) model pioneered by IBM X10. In this model, an application executes across multiple **Places** ($P_0, P_1, \dots, P_{m-1}$), each encapsulating private address space memory, an independent thread scheduler, and an in-memory spatial index.

Global pointers allow activities in one Place to reference objects located in remote Places, while explicit distributed control structures (`async`, `at`, `finish`, `atomic`) govern concurrent activity lifecycles and cross-node communication.

---

## 2. Core Language Primitives in Convect

### 2.1 Async Activity Spawning
The `async` statement spawns a lightweight concurrent activity within the current Place:
```x10
async {
    processSpatialTile(tileId);
}
```
Activities execute cooperatively via work-stealing thread pools, minimizing context-switch overhead during high-velocity stream processing.

### 2.2 Place-Shift (`at`)
The `at (p) statement` shifts execution context from the current Place to destination Place `p`:
```x10
val targetPlace = tileRouter.route(reading.point);
at (targetPlace) async {
    localIndex.insert(reading);
    wal.append(reading);
}
```
Objects captured in the lexical scope of the closure are automatically serialized and transferred across network boundaries.

### 2.3 Finish Barriers (`finish`)
The `finish` statement encloses a block of statements and blocks until all transitively spawned descendant `async` activities have terminated:
```x10
finish {
    for (p in Place.places()) {
        at (p) async {
            localPartitions(p.id).flushCheckpoint();
        }
    }
}
// Guaranteed: all Places completed checkpoints before proceeding
```

---

## 3. Spatiotemporal Memory Layout

### 3.1 Space-Filling Curve Partitioning
Global geographic coordinate space is mapped to an order-24 Hilbert curve ($2^{48}$ discrete 1D cells). The Hilbert domain is split into $M$ contiguous disjoint intervals $[K_p^{min}, K_p^{max})$:

$$\text{Place}(s) = \left\lfloor \frac{\text{Hilbert}(s)}{\text{Span}_p} \right\rfloor$$

This guarantees:
1. **Spatial Locality**: Spatially adjacent sensors reside in the same Place or contiguous neighbor Places.
2. **Deterministic Routing**: Ingest dispatchers evaluate $O(\log M)$ binary search to identify target Place without centralized lock contention.
3. **Bounded Boundary Overhead**: Cross-Place halo communication occurs only along low-dimensional 1D Hilbert interval boundaries.

---

## 4. Fault Tolerance and Recovery

Each Place maintains:
1. **Write-Ahead Log (WAL)**: Per-place append-only binary journal tracking incoming stream updates.
2. **Snapshot Manager**: Periodic asynchronous snapshots of R*-tree and SkipList MemTables.
3. **Consensus Epoch State**: Raft-inspired term numbers and leaseheartbeats to detect network partitions and execute automated partition handovers.
