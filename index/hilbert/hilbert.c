/*
 * hilbert.c - Implementation of 2D Hilbert space-filling curve mapping.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#include "hilbert.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static void rot(uint32_t n, uint32_t *x, uint32_t *y, uint32_t rx, uint32_t ry) {
    if (ry == 0) {
        if (rx == 1) {
            *x = n - 1 - *x;
            *y = n - 1 - *y;
        }
        uint32_t t = *x;
        *x = *y;
        *y = t;
    }
}

uint64_t hilbert_xy_to_d(uint32_t x, uint32_t y, uint32_t order) {
    if (order == 0) return 0;
    if (order > HILBERT_MAX_ORDER) order = HILBERT_MAX_ORDER;

    uint64_t d = 0;
    uint32_t n = 1U << order;

    for (uint32_t s = n / 2; s > 0; s /= 2) {
        uint32_t rx = (x & s) > 0 ? 1 : 0;
        uint32_t ry = (y & s) > 0 ? 1 : 0;
        d += (uint64_t)s * (uint64_t)s * ((3 * rx) ^ ry);
        rot(s, &x, &y, rx, ry);
    }

    return d;
}

void hilbert_d_to_xy(uint64_t d, uint32_t order, uint32_t *out_x, uint32_t *out_y) {
    if (!out_x || !out_y) return;
    if (order == 0) {
        *out_x = 0;
        *out_y = 0;
        return;
    }
    if (order > HILBERT_MAX_ORDER) order = HILBERT_MAX_ORDER;

    uint32_t x = 0;
    uint32_t y = 0;
    uint64_t t = d;

    for (uint32_t s = 1; s < (1U << order); s *= 2) {
        uint32_t rx = 1 & (uint32_t)(t / 2);
        uint32_t ry = 1 & (uint32_t)(t ^ rx);
        rot(s, &x, &y, rx, ry);
        x += s * rx;
        y += s * ry;
        t /= 4;
    }

    *out_x = x;
    *out_y = y;
}

uint64_t hilbert_from_latlon(double lat, double lon, uint32_t order) {
    if (order == 0) return 0;
    if (order > HILBERT_MAX_ORDER) order = HILBERT_MAX_ORDER;

    /* Clamp lat/lon to valid range */
    if (lat < -90.0) lat = -90.0;
    if (lat > 90.0) lat = 90.0;
    if (lon < -180.0) lon = -180.0;
    if (lon > 180.0) lon = 180.0;

    double norm_lat = (lat + 90.0) / 180.0;
    double norm_lon = (lon + 180.0) / 360.0;

    uint32_t max_coord = (1U << order) - 1;

    uint32_t y = (uint32_t)(norm_lat * (double)max_coord);
    uint32_t x = (uint32_t)(norm_lon * (double)max_coord);

    if (x > max_coord) x = max_coord;
    if (y > max_coord) y = max_coord;

    return hilbert_xy_to_d(x, y, order);
}

void hilbert_to_latlon(uint64_t d, uint32_t order, double *out_lat, double *out_lon) {
    if (!out_lat || !out_lon) return;
    if (order == 0) {
        *out_lat = 0.0;
        *out_lon = 0.0;
        return;
    }
    if (order > HILBERT_MAX_ORDER) order = HILBERT_MAX_ORDER;

    uint32_t x = 0, y = 0;
    hilbert_d_to_xy(d, order, &x, &y);

    uint32_t max_coord = 1U << order;

    double norm_lon = ((double)x + 0.5) / (double)max_coord;
    double norm_lat = ((double)y + 0.5) / (double)max_coord;

    *out_lon = norm_lon * 360.0 - 180.0;
    *out_lat = norm_lat * 180.0 - 90.0;
}

int hilbert_point_compare(const spatial_point_t *a, const spatial_point_t *b, uint32_t order) {
    if (!a || !b) return 0;
    uint64_t ha = hilbert_from_latlon(a->lat, a->lon, order);
    uint64_t hb = hilbert_from_latlon(b->lat, b->lon, order);
    if (ha < hb) return -1;
    if (ha > hb) return 1;
    return 0;
}

int hilbert_range_set_init(hilbert_range_set_t *rs, size_t initial_capacity) {
    if (!rs) return -1;
    if (initial_capacity < 8) initial_capacity = 8;
    rs->ranges = (hilbert_range_t *)malloc(initial_capacity * sizeof(hilbert_range_t));
    if (!rs->ranges) return -1;
    rs->count = 0;
    rs->capacity = initial_capacity;
    return 0;
}

int hilbert_range_set_add(hilbert_range_set_t *rs, uint64_t start, uint64_t end) {
    if (!rs) return -1;
    if (start > end) {
        uint64_t tmp = start;
        start = end;
        end = tmp;
    }

    /* Check if this range can merge with the previous range */
    if (rs->count > 0) {
        hilbert_range_t *last = &rs->ranges[rs->count - 1];
        if (start <= last->end + 1) {
            if (end > last->end) {
                last->end = end;
            }
            return 0;
        }
    }

    if (rs->count >= rs->capacity) {
        size_t new_cap = rs->capacity * 2;
        hilbert_range_t *new_ranges = (hilbert_range_t *)realloc(rs->ranges, new_cap * sizeof(hilbert_range_t));
        if (!new_ranges) return -1;
        rs->ranges = new_ranges;
        rs->capacity = new_cap;
    }

    rs->ranges[rs->count].start = start;
    rs->ranges[rs->count].end = end;
    rs->count++;
    return 0;
}

void hilbert_range_set_free(hilbert_range_set_t *rs) {
    if (!rs) return;
    if (rs->ranges) {
        free(rs->ranges);
        rs->ranges = NULL;
    }
    rs->count = 0;
    rs->capacity = 0;
}

static void decompose_quadrant_recursive(uint32_t qx, uint32_t qy, uint32_t qsize,
                                         uint32_t q_order, uint32_t target_order,
                                         uint32_t min_x, uint32_t min_y,
                                         uint32_t max_x, uint32_t max_y,
                                         hilbert_range_set_t *rs) {
    uint32_t q_max_x = qx + qsize - 1;
    uint32_t q_max_y = qy + qsize - 1;

    /* Disjoint */
    if (q_max_x < min_x || qx > max_x || q_max_y < min_y || qy > max_y) {
        return;
    }

    /* Completely enclosed */
    if (qx >= min_x && q_max_x <= max_x && qy >= min_y && q_max_y <= max_y) {
        uint64_t start = hilbert_xy_to_d(qx, qy, target_order);
        uint64_t count = (uint64_t)qsize * (uint64_t)qsize;
        hilbert_range_set_add(rs, start, start + count - 1);
        return;
    }

    /* Base case */
    if (qsize <= 1 || q_order == 0) {
        uint64_t d = hilbert_xy_to_d(qx, qy, target_order);
        hilbert_range_set_add(rs, d, d);
        return;
    }

    /* Subdivide in Hilbert curve visitation order */
    uint32_t half = qsize / 2;
    uint32_t next_order = q_order - 1;

    decompose_quadrant_recursive(qx, qy, half, next_order, target_order, min_x, min_y, max_x, max_y, rs);
    decompose_quadrant_recursive(qx, qy + half, half, next_order, target_order, min_x, min_y, max_x, max_y, rs);
    decompose_quadrant_recursive(qx + half, qy + half, half, next_order, target_order, min_x, min_y, max_x, max_y, rs);
    decompose_quadrant_recursive(qx + half, qy, half, next_order, target_order, min_x, min_y, max_x, max_y, rs);
}

int hilbert_decompose_bbox(const spatial_bbox_t *bbox, uint32_t order,
                          size_t max_ranges, hilbert_range_set_t *out_ranges) {
    if (!bbox || !out_ranges || order == 0) return -1;
    if (order > HILBERT_MAX_ORDER) order = HILBERT_MAX_ORDER;

    if (hilbert_range_set_init(out_ranges, 32) != 0) return -1;

    uint32_t max_coord = (1U << order) - 1;

    double norm_min_lat = fmax(0.0, (bbox->min_lat + 90.0) / 180.0);
    double norm_max_lat = fmin(1.0, (bbox->max_lat + 90.0) / 180.0);
    double norm_min_lon = fmax(0.0, (bbox->min_lon + 180.0) / 360.0);
    double norm_max_lon = fmin(1.0, (bbox->max_lon + 180.0) / 360.0);

    uint32_t min_x = (uint32_t)(norm_min_lon * (double)max_coord);
    uint32_t max_x = (uint32_t)(norm_max_lon * (double)max_coord);
    uint32_t min_y = (uint32_t)(norm_min_lat * (double)max_coord);
    uint32_t max_y = (uint32_t)(norm_max_lat * (double)max_coord);

    if (min_x > max_coord) min_x = max_coord;
    if (max_x > max_coord) max_x = max_coord;
    if (min_y > max_coord) min_y = max_coord;
    if (max_y > max_coord) max_y = max_coord;

    decompose_quadrant_recursive(0, 0, 1U << order, order, order,
                                min_x, min_y, max_x, max_y, out_ranges);

    /* If ranges exceed max_ranges, merge adjacent ranges to reduce fragmentation */
    if (max_ranges > 0 && out_ranges->count > max_ranges) {
        while (out_ranges->count > max_ranges) {
            /* Find minimum gap between two consecutive ranges */
            size_t min_gap_idx = 0;
            uint64_t min_gap = UINT64_MAX;

            for (size_t i = 0; i < out_ranges->count - 1; i++) {
                uint64_t gap = out_ranges->ranges[i + 1].start - out_ranges->ranges[i].end;
                if (gap < min_gap) {
                    min_gap = gap;
                    min_gap_idx = i;
                }
            }

            /* Merge min_gap_idx and min_gap_idx + 1 */
            out_ranges->ranges[min_gap_idx].end = out_ranges->ranges[min_gap_idx + 1].end;
            for (size_t i = min_gap_idx + 1; i < out_ranges->count - 1; i++) {
                out_ranges->ranges[i] = out_ranges->ranges[i + 1];
            }
            out_ranges->count--;
        }
    }

    return 0;
}
