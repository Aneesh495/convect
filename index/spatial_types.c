/*
 * spatial_types.c -- Implementation of common spatial helpers.
 *
 * Copyright 2026 Convect Authors.  All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#include "spatial_types.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

/* -----------------------------------------------------------------------
 * Pi constant -- C11 does not guarantee M_PI, so we define our own.
 * ----------------------------------------------------------------------- */
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* -----------------------------------------------------------------------
 * Degrees-to-radians conversion factor.
 * ----------------------------------------------------------------------- */
#define DEG_TO_RAD (M_PI / 180.0)

/* =======================================================================
 * Result-set lifecycle
 * ======================================================================= */

/*
 * result_set_init -- allocate the backing array for a result set.
 *
 * We clamp the requested capacity to at least 16 so that tiny initial
 * allocations do not cause excessive reallocs on the first few inserts.
 */
int result_set_init(spatial_result_set_t *rs, size_t initial_capacity)
{
    if (!rs) return -1;

    if (initial_capacity < 16) initial_capacity = 16;

    rs->results = (spatial_result_t *)malloc(initial_capacity * sizeof(spatial_result_t));
    if (!rs->results) return -1;

    rs->count    = 0;
    rs->capacity = initial_capacity;
    return 0;
}

/*
 * result_set_add -- append a result, doubling capacity when full.
 *
 * We use a classic doubling strategy because the amortised cost per insert
 * is O(1) and it keeps the number of reallocs logarithmic.
 */
int result_set_add(spatial_result_set_t *rs, spatial_result_t result)
{
    if (!rs) return -1;

    if (rs->count >= rs->capacity) {
        size_t new_cap = rs->capacity * 2;
        spatial_result_t *tmp = (spatial_result_t *)realloc(
            rs->results, new_cap * sizeof(spatial_result_t));
        if (!tmp) return -1;
        rs->results  = tmp;
        rs->capacity = new_cap;
    }

    rs->results[rs->count++] = result;
    return 0;
}

/*
 * result_set_free -- release the backing array.
 *
 * We zero the struct so that accidental double-frees are harmless (free(NULL)
 * is defined as a no-op by the C standard).
 */
void result_set_free(spatial_result_set_t *rs)
{
    if (!rs) return;
    free(rs->results);
    rs->results  = NULL;
    rs->count    = 0;
    rs->capacity = 0;
}

/*
 * compare_results_by_distance -- qsort comparator.
 */
static int compare_results_by_distance(const void *a, const void *b)
{
    double da = ((const spatial_result_t *)a)->distance;
    double db = ((const spatial_result_t *)b)->distance;
    if (da < db) return -1;
    if (da > db) return  1;
    return 0;
}

/*
 * result_set_sort_by_distance -- sort results ascending by distance.
 */
void result_set_sort_by_distance(spatial_result_set_t *rs)
{
    if (!rs || rs->count < 2) return;
    qsort(rs->results, rs->count, sizeof(spatial_result_t),
          compare_results_by_distance);
}

/* =======================================================================
 * Bounding-box helpers
 * ======================================================================= */

/*
 * bbox_contains_point -- inclusive containment test.
 *
 * We use <= and >= rather than < and > because axis-aligned bounding boxes
 * in spatial indices conventionally include their boundary.
 */
bool bbox_contains_point(const spatial_bbox_t *box, double lat, double lon)
{
    if (!box) return false;
    return (lat >= box->min_lat && lat <= box->max_lat &&
            lon >= box->min_lon && lon <= box->max_lon);
}

/*
 * bbox_intersects -- do two boxes overlap?
 *
 * Two AABBs intersect unless they are separated along at least one axis.
 * Touching edges (shared boundary) count as intersection.
 */
bool bbox_intersects(const spatial_bbox_t *a, const spatial_bbox_t *b)
{
    if (!a || !b) return false;
    if (a->max_lat < b->min_lat || a->min_lat > b->max_lat) return false;
    if (a->max_lon < b->min_lon || a->min_lon > b->max_lon) return false;
    return true;
}

/*
 * bbox_area -- area in degree-squared units.
 *
 * This is NOT a geodetic area; it is the simple product of the lat/lon
 * extents.  It is used only for heuristic comparisons in the R-tree split
 * algorithm where relative ordering matters more than absolute values.
 */
double bbox_area(const spatial_bbox_t *box)
{
    if (!box) return 0.0;
    double w = box->max_lon - box->min_lon;
    double h = box->max_lat - box->min_lat;
    if (w < 0.0 || h < 0.0) return 0.0;
    return w * h;
}

/*
 * bbox_union -- minimum enclosing rectangle of two boxes.
 */
spatial_bbox_t bbox_union(const spatial_bbox_t *a, const spatial_bbox_t *b)
{
    spatial_bbox_t u;
    if (!a && !b) {
        u.min_lat = u.min_lon = u.max_lat = u.max_lon = 0.0;
        return u;
    }
    if (!a) return *b;
    if (!b) return *a;

    u.min_lat = (a->min_lat < b->min_lat) ? a->min_lat : b->min_lat;
    u.min_lon = (a->min_lon < b->min_lon) ? a->min_lon : b->min_lon;
    u.max_lat = (a->max_lat > b->max_lat) ? a->max_lat : b->max_lat;
    u.max_lon = (a->max_lon > b->max_lon) ? a->max_lon : b->max_lon;
    return u;
}

/*
 * bbox_margin -- half-perimeter in degree units.
 *
 * Used by the R*-tree split-axis selection: the axis whose distribution of
 * candidate splits yields the smallest total margin sum is chosen.
 */
double bbox_margin(const spatial_bbox_t *box)
{
    if (!box) return 0.0;
    double w = box->max_lon - box->min_lon;
    double h = box->max_lat - box->min_lat;
    if (w < 0.0) w = 0.0;
    if (h < 0.0) h = 0.0;
    return w + h;
}

/*
 * bbox_overlap_area -- intersection area of two boxes.
 */
double bbox_overlap_area(const spatial_bbox_t *a, const spatial_bbox_t *b)
{
    if (!a || !b) return 0.0;

    double ov_min_lat = (a->min_lat > b->min_lat) ? a->min_lat : b->min_lat;
    double ov_min_lon = (a->min_lon > b->min_lon) ? a->min_lon : b->min_lon;
    double ov_max_lat = (a->max_lat < b->max_lat) ? a->max_lat : b->max_lat;
    double ov_max_lon = (a->max_lon < b->max_lon) ? a->max_lon : b->max_lon;

    double w = ov_max_lon - ov_min_lon;
    double h = ov_max_lat - ov_min_lat;

    if (w <= 0.0 || h <= 0.0) return 0.0;
    return w * h;
}

/*
 * bbox_enlargement -- additional area needed to include (lat, lon).
 *
 * Returns 0 if the point is already inside the box.
 */
double bbox_enlargement(const spatial_bbox_t *box, double lat, double lon)
{
    if (!box) return 0.0;

    double old_area = bbox_area(box);

    /* Build the enlarged box */
    spatial_bbox_t enlarged;
    enlarged.min_lat = (lat < box->min_lat) ? lat : box->min_lat;
    enlarged.min_lon = (lon < box->min_lon) ? lon : box->min_lon;
    enlarged.max_lat = (lat > box->max_lat) ? lat : box->max_lat;
    enlarged.max_lon = (lon > box->max_lon) ? lon : box->max_lon;

    return bbox_area(&enlarged) - old_area;
}

/*
 * bbox_min_dist_to_point -- minimum Euclidean distance in degree space.
 *
 * Used by the R-tree kNN search to prune branches whose minimum possible
 * distance exceeds the current k-th nearest distance.  We compute the
 * squared distance to avoid the sqrt; callers comparing distances should
 * compare squared values consistently.
 *
 * Actually, for consistency with point_distance_euclidean (which returns
 * the actual distance, not squared), we return the sqrt here.
 */
double bbox_min_dist_to_point(const spatial_bbox_t *box, double lat, double lon)
{
    if (!box) return 0.0;

    /* Clamp the query point to the nearest point on the box boundary */
    double clat = lat;
    double clon = lon;

    if (clat < box->min_lat) clat = box->min_lat;
    if (clat > box->max_lat) clat = box->max_lat;
    if (clon < box->min_lon) clon = box->min_lon;
    if (clon > box->max_lon) clon = box->max_lon;

    double dlat = lat - clat;
    double dlon = lon - clon;
    return sqrt(dlat * dlat + dlon * dlon);
}

/* =======================================================================
 * Distance functions
 * ======================================================================= */

/*
 * point_distance_haversine -- great-circle distance using the Haversine
 * formula.
 *
 * The Haversine formula is numerically stable for nearly-antipodal points
 * and is accurate to ~0.5% (it models the Earth as a perfect sphere).
 * For applications that need higher precision, the Vincenty inverse
 * formula on the WGS-84 ellipsoid should be used instead, but that is
 * significantly more expensive and unnecessary for index pruning.
 *
 * Returns distance in metres.
 *
 * Formula:
 *   a = sin^2(dlat/2) + cos(lat1) * cos(lat2) * sin^2(dlon/2)
 *   c = 2 * atan2(sqrt(a), sqrt(1 - a))
 *   d = R * c
 */
double point_distance_haversine(double lat1, double lon1,
                                double lat2, double lon2)
{
    double rlat1 = lat1 * DEG_TO_RAD;
    double rlat2 = lat2 * DEG_TO_RAD;
    double dlat  = (lat2 - lat1) * DEG_TO_RAD;
    double dlon  = (lon2 - lon1) * DEG_TO_RAD;

    double sin_dlat = sin(dlat * 0.5);
    double sin_dlon = sin(dlon * 0.5);

    double a = sin_dlat * sin_dlat +
               cos(rlat1) * cos(rlat2) * sin_dlon * sin_dlon;

    /* atan2 is preferred over asin for numerical stability when a is
     * close to 1 (nearly-antipodal points). */
    double c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));

    return EARTH_RADIUS_M * c;
}

/*
 * point_distance_euclidean -- simple L2 distance in degree-space.
 *
 * This is the cheapest possible "distance" and is useful for relative
 * ordering in a small local area.  The result is NOT in metres -- it is
 * in units of degrees.  One degree of latitude is ~111 km, but one degree
 * of longitude varies with latitude.  Treat this as a unitless proximity
 * score.
 */
double point_distance_euclidean(double lat1, double lon1,
                                double lat2, double lon2)
{
    double dlat = lat2 - lat1;
    double dlon = lon2 - lon1;
    return sqrt(dlat * dlat + dlon * dlon);
}
