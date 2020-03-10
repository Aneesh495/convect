/*
 * rtree.h -- R*-tree spatial index for the convect engine.
 *
 * This is a full R*-tree implementation with:
 *   - Configurable branching factor (min/max children per node).
 *   - Point and rectangle insertion with choose-subtree using minimum
 *     overlap enlargement for leaf-level decisions.
 *   - Forced reinsertion on overflow (30% of entries) before splitting,
 *     per the R*-tree paper (Beckmann et al., 1990).
 *   - Split algorithm: choose split axis by minimum margin sum, then
 *     choose split index by minimum overlap.
 *   - Range query (bounding-box intersection search).
 *   - k-nearest-neighbor search using a priority-queue based
 *     branch-and-bound traversal.
 *   - Point-in-radius query.
 *   - Deletion by ID.
 *   - Bulk loading via Sort-Tile-Recursive (STR) packing for efficient
 *     initial construction.
 *   - Statistics (height, node count, entry count, fill factor).
 *
 * The tree stores spatial_entry_t values (defined in spatial_types.h) and
 * supports both point features (degenerate bounding boxes) and area
 * features (proper rectangles).
 *
 * Copyright 2026 Convect Authors.  All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef CONVECT_RTREE_H
#define CONVECT_RTREE_H

#include "../spatial_types.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* --------------------------------------------------------------------------
 * Configuration defaults.
 *
 * RTREE_MIN_CHILDREN is typically 40% of MAX to guarantee good node
 * utilisation while still permitting enough redistribution freedom during
 * splits and reinsertion.
 * -------------------------------------------------------------------------- */
#define RTREE_DEFAULT_MIN_CHILDREN  4
#define RTREE_DEFAULT_MAX_CHILDREN 16

/* Fraction of entries to forcibly reinsert before splitting a node.
 * The R*-tree paper recommends p = 0.30. */
#define RTREE_REINSERT_FRACTION 0.30

/* --------------------------------------------------------------------------
 * rtree_node_t -- internal and leaf nodes of the R-tree.
 *
 * Internal nodes store child pointers; leaf nodes store spatial_entry_t
 * values directly.  We use a tagged union: if `is_leaf` is true, the
 * `entries` array is valid; otherwise `children` is valid.
 *
 * Each node tracks its own bounding box (the MBR of all descendants).
 * -------------------------------------------------------------------------- */
typedef struct rtree_node {
    bool              is_leaf;
    int               count;       /* number of entries or children */
    spatial_bbox_t    bbox;        /* minimum bounding rectangle    */
    struct rtree_node *parent;

    /* Branching factor -- stored per-node so the tree struct does not need
     * to be threaded through every internal function. */
    int               max_children;

    /* Tagged union: exactly one of these is valid per node. */
    union {
        struct rtree_node **children;   /* internal: child node pointers */
        spatial_entry_t    *entries;    /* leaf: data entries            */
    };

    /* Each child or entry has a corresponding bounding box.  For internal
     * nodes this is the MBR of the child subtree.  For leaf nodes it is
     * the entry's own bbox (duplicated from entries[i].bbox for convenience
     * during split/choose-subtree calculations). */
    spatial_bbox_t *child_bboxes;
} rtree_node_t;

/* --------------------------------------------------------------------------
 * rtree_stats_t -- tree-level statistics.
 * -------------------------------------------------------------------------- */
typedef struct rtree_stats {
    int    height;        /* tree height (1 == root is a leaf) */
    size_t node_count;    /* total number of nodes             */
    size_t entry_count;   /* total number of data entries      */
    double avg_fill;      /* average node fill factor [0, 1]   */
} rtree_stats_t;

/* --------------------------------------------------------------------------
 * rtree_t -- the top-level R-tree handle.
 * -------------------------------------------------------------------------- */
typedef struct rtree {
    rtree_node_t *root;
    int           min_children;
    int           max_children;
    size_t        size;           /* total entries in the tree */
    int           height;         /* cached height             */
} rtree_t;

/* -- Lifecycle ------------------------------------------------------------ */

/* Create an empty R-tree with the given branching factor bounds.
 * Pass 0 for either to use the default (4 / 16). */
rtree_t *rtree_create(int min_children, int max_children);

/* Destroy the tree and free all nodes.  Does NOT free payloads. */
void rtree_destroy(rtree_t *tree);

/* -- Insertion ------------------------------------------------------------ */

/* Insert a spatial entry into the tree. */
int rtree_insert(rtree_t *tree, spatial_entry_t entry);

/* Insert a point feature (convenience wrapper that builds a degenerate
 * bounding box from lat/lon). */
int rtree_insert_point(rtree_t *tree, uint64_t id,
                       double lat, double lon, void *payload);

/* -- Bulk loading --------------------------------------------------------- */

/* Build an R-tree from a pre-existing array of entries using the
 * Sort-Tile-Recursive (STR) packing algorithm.  Produces a well-packed
 * tree with high node utilisation.
 *
 * The input array is modified (sorted) in place.  Returns a new rtree_t
 * or NULL on failure. */
rtree_t *rtree_bulk_load(spatial_entry_t *entries, size_t count,
                         int min_children, int max_children);

/* -- Queries -------------------------------------------------------------- */

/* Range query: find all entries whose bounding box intersects `query_bbox`.
 * Results are appended to `rs`. */
int rtree_query_range(const rtree_t *tree, const spatial_bbox_t *query_bbox,
                      spatial_result_set_t *rs);

/* k-nearest-neighbor query: find the k closest entries to (lat, lon).
 * Distance is Euclidean in degree-space (fast, suitable for index pruning).
 * Results are appended to `rs`, sorted by ascending distance. */
int rtree_query_knn(const rtree_t *tree, double lat, double lon,
                    int k, spatial_result_set_t *rs);

/* Radius query: find all entries within `radius_m` metres of (lat, lon).
 * Uses Haversine distance.  Results are appended to `rs`. */
int rtree_query_radius(const rtree_t *tree, double lat, double lon,
                       double radius_m, spatial_result_set_t *rs);

/* -- Deletion ------------------------------------------------------------- */

/* Delete the entry with the given ID.  Returns 0 on success, -1 if not
 * found. */
int rtree_delete(rtree_t *tree, uint64_t id);

/* -- Statistics ----------------------------------------------------------- */

/* Collect tree statistics into `stats`. */
void rtree_stats(const rtree_t *tree, rtree_stats_t *stats);

#ifdef __cplusplus
}
#endif

#endif /* CONVECT_RTREE_H */
