# Distributed Spatial Indexing and Algorithmic Foundations

This document details the spatial indexing algorithms, space-filling curve linearization,
and computational geometry primitives used in the Convect engine.

## 1. Space-Filling Curve Linearization: Hilbert vs Morton (Z-Order)

To distribute 2D geospatial coordinates across 1D partitioned cluster places,
Convect projects geographic coordinates (lat, lon) onto a space-filling curve.

### Locality Preservation
A space-filling curve maps continuous multidimensional space onto a 1D line while
attempting to preserve spatial locality: points that are close in 2D space should
be close along the 1D curve.

```
       Morton (Z-Order) Curve                      Hilbert Curve
       +---+   +---+                               +-------+
       |   |   |   |                               |       |
       +---+---+---+                               +---+   +---+
       |   |   |   |                                   |   |   |
       +---+   +---+                               +---+   +---+
  (Contains large diagonal jumps)              (Continuous, strictly adjacent)
```

- **Morton (Z-Order) Curve**: Formed by bitwise interleaving binary coordinates.
  While computationally trivial (requiring only bit shifts), it exhibits severe
  discontinuities. Crossing quadrant boundaries causes large numerical jumps between
  geographically adjacent points, leading to fragmented range scans.
- **Hilbert Curve**: A continuous fractal curve where each transition between
  consecutive 1D indices moves to a strictly adjacent orthogonal grid cell.
  The maximum bounding box diameter for a given interval length on a Hilbert curve
  is provably superior to Morton order.

### Implementation Details in `index/hilbert/`
Convect implements a state-based 2D Hilbert projection supporting resolutions up to order 31
(generating 62-bit coordinates with sub-millimeter geographic precision).
For a bounding box query `B`, the algorithm performs quadtree-driven range decomposition:
subdividing regions that partially overlap `B` and emitting contiguous 1D intervals
`[start_h, end_h]` to enable contiguous index scans.

```
+-------------------------------------------------------------+
| Hilbert Bounding Box Range Decomposition                    |
|                                                             |
|  1. Start at root quad of curve at order N                  |
|  2. If quadrant is disjoint from B -> prune                 |
|  3. If quadrant is fully enclosed by B -> emit range        |
|  4. If quadrant partially intersects B -> subdivide into 4  |
|  5. If emitted ranges exceed max_ranges -> merge min gap    |
+-------------------------------------------------------------+
```

## 2. R*-Tree Spatial Index (`index/rtree/`)

For in-memory indexing of observations within each Place, Convect uses an R*-tree
(Beckmann, Kriegel, Schneider, Seeger, 1990).

### Key Algorithmic Distinctions over Standard R-Tree:

1. **ChooseSubtree with Overlap Minimization**:
   - For insertions into non-leaf nodes, chooses child node minimizing area enlargement.
   - For insertions into leaf nodes, chooses child node minimizing the increase in
     bounding box overlap with sibling nodes. Overlap reduction dramatically decreases
     the number of paths explored during range and k-NN searches.

2. **Forced Reinsertion on Overflow**:
   - When a node exceeds `max_children`, rather than immediately executing an expensive split,
     the tree sorts all entries by distance from the node center.
   - The top 30% most distant entries are removed and reinserted starting from the root.
   - This reorganizes node geometry dynamically, improving tree packing and reducing perimeter margins.

3. **Sort-Tile-Recursive (STR) Bulk Loading**:
   - For batch streams, entries are sorted along the X axis into vertical slices,
     and each slice is sorted along the Y axis.
   - Leaves are packed to 100% capacity, yielding optimal tree height and query traversal paths.

## 3. Real-Time Spatial Anomaly Detection

### Local Outlier Factor (LOF)
Detects observations whose density is substantially lower than that of their k-nearest neighbors:

1. **k-distance**: Distance from point p to its k-th nearest neighbor.
2. **Reachability Distance**:
   $$reach\_dist_k(p, o) = \max(k\_dist(o), dist(p, o))$$
3. **Local Reachability Density (LRD)**:
   $$lrd_k(p) = \frac{|N_k(p)|}{\sum_{o \in N_k(p)} reach\_dist_k(p, o)}$$
4. **LOF Score**:
   $$LOF_k(p) = \frac{\sum_{o \in N_k(p)} \frac{lrd_k(o)}{lrd_k(p)}}{|N_k(p)|}$$

An LOF score greater than 1.5 indicates that point p is situated in a sparse pocket
relative to nearby stations, signaling an isolated sensor anomaly.

### Getis-Ord Gi* Hotspot Statistic
Identifies statistically significant spatial clustering of high or low measurements:

$$G_i^* = \frac{\sum_{j=1}^n w_{ij} x_j - \bar{X} \sum_{j=1}^n w_{ij}}{S \sqrt{\frac{n \sum_{j=1}^n w_{ij}^2 - (\sum_{j=1}^n w_{ij})^2}{n - 1}}}$$

Where:
- $w_{ij}$ is the spatial weight between stations i and j (1 if within neighborhood distance, 0 otherwise).
- $\bar{X}$ is the global sample mean.
- $S$ is the global standard deviation.

A standard normal Z-score exceeding +1.96 represents a hot spot significant at $p < 0.05$.
