/*
 * geohash.h - Geohash encoding, decoding, and neighborhood operations.
 *
 * Geohash is a hierarchical spatial index that subdivides the globe into a
 * grid of cells encoded as base32 strings or compact 64-bit integers.
 * Points with common geohash prefixes share geographic proximity.
 *
 * Supported features:
 *   - Base32 string encoding and decoding (precision 1 to 12 characters)
 *   - Binary 64-bit integer geohash encoding and decoding
 *   - Geohash cell bounding box calculation and error margins
 *   - 8-directional neighbor cell calculation (N, S, E, W, NE, NW, SE, SW)
 *   - Enumerate all geohash cells covering a given bounding box at target precision
 *   - Longest common prefix calculation for spatial clustering
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef CONVECT_GEOHASH_H
#define CONVECT_GEOHASH_H

#include "../spatial_types.h"
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define GEOHASH_MAX_PRECISION 12

typedef enum {
    GEOHASH_DIR_NORTH = 0,
    GEOHASH_DIR_EAST  = 1,
    GEOHASH_DIR_SOUTH = 2,
    GEOHASH_DIR_WEST  = 3
} geohash_direction_t;

typedef struct {
    char north[GEOHASH_MAX_PRECISION + 1];
    char south[GEOHASH_MAX_PRECISION + 1];
    char east[GEOHASH_MAX_PRECISION + 1];
    char west[GEOHASH_MAX_PRECISION + 1];
    char north_east[GEOHASH_MAX_PRECISION + 1];
    char north_west[GEOHASH_MAX_PRECISION + 1];
    char south_east[GEOHASH_MAX_PRECISION + 1];
    char south_west[GEOHASH_MAX_PRECISION + 1];
} geohash_neighbors_t;

/* Encode latitude and longitude into a null-terminated base32 geohash string.
 * out_hash must have capacity of at least (precision + 1) bytes.
 * Returns 0 on success, -1 on invalid coordinates or precision. */
int geohash_encode(double lat, double lon, size_t precision, char *out_hash);

/* Decode a base32 geohash string into latitude and longitude center point.
 * Also returns the bounding box envelope of the geohash cell.
 * Returns 0 on success, -1 on invalid geohash character. */
int geohash_decode(const char *hash, double *out_lat, double *out_lon, spatial_bbox_t *out_bbox);

/* Encode coordinates into a 64-bit integer binary geohash with given number of bits (1 to 64). */
uint64_t geohash_encode_bits(double lat, double lon, uint8_t num_bits);

/* Decode 64-bit integer binary geohash into center coordinates and bounding box. */
void geohash_decode_bits(uint64_t hash_bits, uint8_t num_bits,
                         double *out_lat, double *out_lon, spatial_bbox_t *out_bbox);

/* Calculate all 8 neighboring geohashes of the given hash string. */
int geohash_get_neighbors(const char *hash, geohash_neighbors_t *out_neighbors);

/* Calculate the direct neighbor in one cardinal direction (N, E, S, W).
 * out_neighbor must have capacity at least strlen(hash) + 1. */
int geohash_get_neighbor(const char *hash, geohash_direction_t dir, char *out_neighbor);

/* Determine optimal geohash precision to cover a bounding box without excessive cells. */
size_t geohash_optimal_precision(const spatial_bbox_t *bbox);

/* Compute bounding box dimensions (lat_height, lon_width) for a given precision. */
void geohash_cell_dimensions(size_t precision, double *out_lat_deg, double *out_lon_deg);

/* Compute length of longest common prefix between two geohashes. */
size_t geohash_common_prefix_length(const char *hash1, const char *hash2);

/* Enumerate all geohash strings of target precision covering the given bounding box.
 * Returns a dynamically allocated array of strings (caller must free each string and array).
 * out_count receives the number of hashes. */
char **geohash_cover_bbox(const spatial_bbox_t *bbox, size_t precision, size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif /* CONVECT_GEOHASH_H */
