/*
 * quadtree.h - Point-region quadtree for adaptive spatial partitioning.
 *
 * Implements a 2D PR-quadtree tailored for dense sensor clusters and spatial
 * boundary routing. Each internal node subdivides into four quadrants (NW, NE,
 * SW, SE) once its bucket capacity is exceeded, up to a configurable maximum depth.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef CONVECT_QUADTREE_H
#define CONVECT_QUADTREE_H

#include "../spatial_types.h"
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define QUADTREE_DEFAULT_MAX_DEPTH 16
#define QUADTREE_DEFAULT_CAPACITY  32

typedef struct quadtree_node quadtree_node_t;

typedef struct quadtree_stats {
    size_t node_count;
    size_t leaf_count;
    size_t point_count;
    size_t max_depth_reached;
} quadtree_stats_t;

typedef struct quadtree {
    quadtree_node_t *root;
    spatial_bbox_t   bounds;
    size_t           capacity;
    size_t           max_depth;
    size_t           size;
} quadtree_t;

typedef bool (*quadtree_visitor_fn)(uint64_t id, double lat, double lon, void *payload, void *user_data);

/* Create a quadtree bounded by the given geographic extent. */
quadtree_t *quadtree_create(const spatial_bbox_t *bounds, size_t capacity, size_t max_depth);

/* Destroy the quadtree and release all internal node memory. */
void quadtree_destroy(quadtree_t *qt);

/* Insert a point into the quadtree. */
int quadtree_insert(quadtree_t *qt, uint64_t id, double lat, double lon, void *payload);

/* Execute a rectangular range query. */
int quadtree_query_range(const quadtree_t *qt, const spatial_bbox_t *bbox, spatial_result_set_t *rs);

/* Find all points within radius_m metres of (lat, lon) using Haversine distance. */
int quadtree_query_radius(const quadtree_t *qt, double lat, double lon, double radius_m, spatial_result_set_t *rs);

/* Find k-nearest neighbors to (lat, lon). */
int quadtree_query_knn(const quadtree_t *qt, double lat, double lon, size_t k, spatial_result_set_t *rs);

/* Delete an item by ID. Returns 0 if found and deleted, -1 if not found. */
int quadtree_delete(quadtree_t *qt, uint64_t id);

/* Traverse all points in the quadtree invoking the visitor callback. */
void quadtree_traverse(const quadtree_t *qt, quadtree_visitor_fn visitor, void *user_data);

/* Compute depth and structural statistics of the quadtree. */
void quadtree_stats(const quadtree_t *qt, quadtree_stats_t *stats);

#ifdef __cplusplus
}
#endif

#endif /* CONVECT_QUADTREE_H */
