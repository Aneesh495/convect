/*
 * spatial_types.h -- Common types and utilities for the convect spatial index.
 *
 * This header defines the fundamental geometric primitives (points, bounding
 * boxes), the entry/result types shared by every index structure, and a small
 * library of helper functions (distance, containment, intersection, area).
 *
 * All geographic coordinates follow the (latitude, longitude) convention with
 * latitude in [-90, 90] and longitude in [-180, 180].  Distances can be
 * computed either as cheap Euclidean approximations (for small, local regions)
 * or as proper great-circle Haversine distances (for global accuracy).
 *
 * Copyright 2026 Convect Authors.  All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef CONVECT_SPATIAL_TYPES_H
#define CONVECT_SPATIAL_TYPES_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* --------------------------------------------------------------------------
 * Mean Earth radius in metres (WGS-84 volumetric mean).
 * Used by the Haversine distance function.
 * -------------------------------------------------------------------------- */
#define EARTH_RADIUS_M 6371008.8

/* --------------------------------------------------------------------------
 * spatial_point_t -- a single WGS-84 coordinate.
 *
 * We store latitude and longitude as double-precision floats.  This gives us
 * sub-millimetre resolution, which is more than sufficient for any practical
 * geospatial workload.
 * -------------------------------------------------------------------------- */
typedef struct spatial_point {
    double lat;   /* degrees north, [-90, 90]   */
    double lon;   /* degrees east, [-180, 180]   */
} spatial_point_t;

/* --------------------------------------------------------------------------
 * spatial_bbox_t -- axis-aligned bounding box in geographic coordinates.
 *
 * The box is defined by its south-west (min_lat, min_lon) and north-east
 * (max_lat, max_lon) corners.  We do NOT currently handle anti-meridian
 * wrapping; callers that need that should split the query into two boxes.
 * -------------------------------------------------------------------------- */
typedef struct spatial_bbox {
    double min_lat;
    double min_lon;
    double max_lat;
    double max_lon;
} spatial_bbox_t;

/* --------------------------------------------------------------------------
 * spatial_entry_t -- an indexed entity.
 *
 * Each entry has a unique 64-bit identifier, a bounding box that describes
 * its spatial extent, and an optional opaque payload pointer.  For point
 * features the bounding box is degenerate (min == max).
 * -------------------------------------------------------------------------- */
typedef struct spatial_entry {
    uint64_t       id;       /* unique key (e.g. tile ID, feature ID) */
    spatial_bbox_t bbox;     /* spatial extent                        */
    void          *payload;  /* opaque user data, may be NULL         */
} spatial_entry_t;

/* --------------------------------------------------------------------------
 * spatial_result_t -- a single hit returned by a query.
 *
 * Carries the matched entry's ID, its distance from the query reference
 * (0.0 for pure intersection queries), and the optional payload.
 * -------------------------------------------------------------------------- */
typedef struct spatial_result {
    uint64_t id;
    double   distance;   /* metres for Haversine, raw units for Euclidean */
    void    *payload;
} spatial_result_t;

/* --------------------------------------------------------------------------
 * spatial_result_set_t -- growable array of query results.
 *
 * Callers should use result_set_init / result_set_add / result_set_free to
 * manage the lifetime.  The array doubles in capacity on overflow.
 * -------------------------------------------------------------------------- */
typedef struct spatial_result_set {
    spatial_result_t *results;
    size_t            count;
    size_t            capacity;
} spatial_result_set_t;

/* -- Result-set lifecycle ------------------------------------------------- */

/* Initialise a result set with a given starting capacity.  Returns 0 on
 * success, -1 if the allocation fails. */
int  result_set_init(spatial_result_set_t *rs, size_t initial_capacity);

/* Append one result.  Grows the backing array if necessary.  Returns 0 on
 * success, -1 on allocation failure. */
int  result_set_add(spatial_result_set_t *rs, spatial_result_t result);

/* Release all memory owned by the result set.  The struct itself is NOT
 * freed (it may be stack-allocated). */
void result_set_free(spatial_result_set_t *rs);

/* Sort the result set by ascending distance.  Useful for kNN queries. */
void result_set_sort_by_distance(spatial_result_set_t *rs);

/* -- Bounding-box helpers ------------------------------------------------- */

/* Return true if the point (lat, lon) lies inside the box (inclusive). */
bool bbox_contains_point(const spatial_bbox_t *box, double lat, double lon);

/* Return true if the two boxes share any area (touching edges count). */
bool bbox_intersects(const spatial_bbox_t *a, const spatial_bbox_t *b);

/* Area of the box in degrees-squared.  Useful for overlap heuristics in
 * the R-tree.  Returns 0 for degenerate (point/line) boxes. */
double bbox_area(const spatial_bbox_t *box);

/* Return the smallest box that contains both a and b. */
spatial_bbox_t bbox_union(const spatial_bbox_t *a, const spatial_bbox_t *b);

/* Sum of the half-perimeter (width + height) in degrees.  Used by the
 * R*-tree split algorithm to evaluate split quality. */
double bbox_margin(const spatial_bbox_t *box);

/* Compute the overlap area between two boxes.  Returns 0 if they do not
 * intersect. */
double bbox_overlap_area(const spatial_bbox_t *a, const spatial_bbox_t *b);

/* Compute the area enlargement required to include a point in a box. */
double bbox_enlargement(const spatial_bbox_t *box, double lat, double lon);

/* Return the minimum distance from a point to the nearest edge of a
 * bounding box (Euclidean in degree space).  Returns 0 if the point is
 * inside the box.  Used by kNN branch-and-bound pruning. */
double bbox_min_dist_to_point(const spatial_bbox_t *box, double lat, double lon);

/* -- Distance functions --------------------------------------------------- */

/* Great-circle distance in metres between two geographic points using the
 * Haversine formula.  Accurate to ~0.5% for any two points on Earth. */
double point_distance_haversine(double lat1, double lon1,
                                double lat2, double lon2);

/* Cheap Euclidean distance in "degree units".  Good enough for relative
 * ordering within a small region (< ~100 km).  NOT metres. */
double point_distance_euclidean(double lat1, double lon1,
                                double lat2, double lon2);

#ifdef __cplusplus
}
#endif

#endif /* CONVECT_SPATIAL_TYPES_H */
