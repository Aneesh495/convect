/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: index/h3/h3_lite.h
 *
 * Hexagonal discrete global grid system (DGGS) implementation inspired by
 * Uber H3. Supports resolutions 0..15, 64-bit cell indexing, neighbor
 * discovery (k-ring), and geographic coordinate projections.
 */

#ifndef CONVECT_H3_LITE_H
#define CONVECT_H3_LITE_H

#include <stdint.h>
#include <stdbool.h>
#include "../spatial_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define CONVECT_H3_MAX_RES 15
#define CONVECT_H3_NUM_BASE_CELLS 122

/* 64-bit H3 index format:
 * bits 63..59: Mode (1 = Hexagon)
 * bits 58..55: Reserved
 * bits 54..52: Resolution (0..15)
 * bits 51..45: Base cell (0..121)
 * bits 44..0:  Child direction digits (3 bits per resolution)
 */
typedef uint64_t convect_h3_index_t;

#define CONVECT_H3_NULL 0ULL

/**
 * Encode geographic coordinate (lat, lon) at specified resolution (0..15)
 * into a 64-bit hexagonal discrete global grid index.
 */
convect_h3_index_t convect_h3_from_geo(double lat, double lon, int res);

/**
 * Decode a 64-bit hexagonal discrete global grid index into its geographic center (lat, lon).
 */
bool convect_h3_to_geo(convect_h3_index_t h3, double *lat_out, double *lon_out);

/**
 * Get resolution (0..15) of an H3 index.
 */
int convect_h3_get_resolution(convect_h3_index_t h3);

/**
 * Get base cell (0..121) of an H3 index.
 */
int convect_h3_get_base_cell(convect_h3_index_t h3);

/**
 * Return parent H3 index at target resolution (parent_res < current_res).
 */
convect_h3_index_t convect_h3_to_parent(convect_h3_index_t h3, int parent_res);

/**
 * Return immediate 6 hexagonal neighbors of the given cell.
 * neighbors array must be sized for at least 6 uint64_t entries.
 * Returns the count of valid neighbors found (normally 6, or 5 for pentagons).
 */
int convect_h3_get_neighbors(convect_h3_index_t h3, convect_h3_index_t *neighbors);

/**
 * Compute k-ring neighborhood of radius k around origin cell.
 * k = 0: 1 cell (origin)
 * k = 1: 7 cells (origin + 6 immediate neighbors)
 * k = 2: 19 cells
 * Max out_cells array size required: 1 + 3 * k * (k + 1).
 * Returns the total number of cells populated in out_cells.
 */
int convect_h3_k_ring(convect_h3_index_t origin, int k, convect_h3_index_t *out_cells, int max_capacity);

/**
 * Format 64-bit H3 index as standard 15-character hexadecimal string.
 */
void convect_h3_to_string(convect_h3_index_t h3, char *buf, size_t buf_len);

/**
 * Parse standard hexadecimal string into 64-bit H3 index.
 */
convect_h3_index_t convect_h3_from_string(const char *str);

#ifdef __cplusplus
}
#endif

#endif /* CONVECT_H3_LITE_H */
