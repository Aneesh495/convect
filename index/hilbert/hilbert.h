/*
 * hilbert.h - Hilbert space-filling curve index and range decomposition.
 *
 * Implements 2D Hilbert curve mapping algorithms. The Hilbert curve maps 2D
 * coordinates onto a continuous 1D space-filling curve that preserves spatial
 * locality significantly better than Z-order (Morton) curves.
 *
 * This component provides:
 *   - Grid (x, y) to Hilbert distance d mapping (and inverse)
 *   - WGS-84 (lat, lon) geographic projection to Hilbert index
 *   - Compact 64-bit Hilbert indices for order up to 31
 *   - Hilbert range decomposition: decomposing a 2D bounding box into
 *     a minimal set of 1D contiguous Hilbert intervals [start, end]
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef CONVECT_HILBERT_H
#define CONVECT_HILBERT_H

#include "../spatial_types.h"
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HILBERT_MAX_ORDER 31

typedef struct {
    uint64_t start;
    uint64_t end;
} hilbert_range_t;

typedef struct {
    hilbert_range_t *ranges;
    size_t count;
    size_t capacity;
} hilbert_range_set_t;

/* Map 2D integer grid coordinates (x, y) to a 1D Hilbert index of given order (1 to 31). */
uint64_t hilbert_xy_to_d(uint32_t x, uint32_t y, uint32_t order);

/* Map a 1D Hilbert index back to 2D integer grid coordinates (x, y). */
void hilbert_d_to_xy(uint64_t d, uint32_t order, uint32_t *out_x, uint32_t *out_y);

/* Project WGS-84 geographic coordinates (lat, lon) to a 64-bit Hilbert index. */
uint64_t hilbert_from_latlon(double lat, double lon, uint32_t order);

/* Reverse project a 64-bit Hilbert index back to the geographic center of the cell. */
void hilbert_to_latlon(uint64_t d, uint32_t order, double *out_lat, double *out_lon);

/* Compare two spatial points by their Hilbert index at the specified order. */
int hilbert_point_compare(const spatial_point_t *a, const spatial_point_t *b, uint32_t order);

/* Initialize a Hilbert range set. */
int hilbert_range_set_init(hilbert_range_set_t *rs, size_t initial_capacity);

/* Add a range to the range set, automatically merging contiguous or overlapping ranges. */
int hilbert_range_set_add(hilbert_range_set_t *rs, uint64_t start, uint64_t end);

/* Release memory owned by a Hilbert range set. */
void hilbert_range_set_free(hilbert_range_set_t *rs);

/* Decompose a 2D bounding box into a set of 1D Hilbert ranges at target order.
 * max_ranges limits the fragmentation (merges small gaps if range count exceeds limit). */
int hilbert_decompose_bbox(const spatial_bbox_t *bbox, uint32_t order,
                          size_t max_ranges, hilbert_range_set_t *out_ranges);

#ifdef __cplusplus
}
#endif

#endif /* CONVECT_HILBERT_H */
