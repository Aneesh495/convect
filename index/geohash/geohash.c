/*
 * geohash.c - Implementation of Geohash spatial encoding and neighbor queries.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#include "geohash.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

static const char BASE32_CHARS[] = "0123456789bcdefghjkmnpqrstuvwxyz";

static const int8_t BASE32_DECODE_MAP[256] = {
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
     0,  1,  2,  3,  4,  5,  6,  7,  8,  9, -1, -1, -1, -1, -1, -1,
    -1, -1, 10, 11, 12, 13, 14, 15, 16, -1, 17, 18, -1, 19, 20, -1,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, -1, -1, -1, -1, -1,
    -1, -1, 10, 11, 12, 13, 14, 15, 16, -1, 17, 18, -1, 19, 20, -1,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
};

int geohash_encode(double lat, double lon, size_t precision, char *out_hash) {
    if (!out_hash || precision == 0 || precision > GEOHASH_MAX_PRECISION) {
        return -1;
    }
    if (lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) {
        return -1;
    }

    double lat_min = -90.0, lat_max = 90.0;
    double lon_min = -180.0, lon_max = 180.0;

    bool is_even = true; /* Even bits are longitude, odd bits are latitude */
    uint32_t ch = 0;
    int bit = 0;
    size_t hash_idx = 0;

    while (hash_idx < precision) {
        if (is_even) {
            double mid = (lon_min + lon_max) * 0.5;
            if (lon >= mid) {
                ch |= (1U << (4 - bit));
                lon_min = mid;
            } else {
                lon_max = mid;
            }
        } else {
            double mid = (lat_min + lat_max) * 0.5;
            if (lat >= mid) {
                ch |= (1U << (4 - bit));
                lat_min = mid;
            } else {
                lat_max = mid;
            }
        }

        is_even = !is_even;
        if (bit < 4) {
            bit++;
        } else {
            out_hash[hash_idx++] = BASE32_CHARS[ch];
            bit = 0;
            ch = 0;
        }
    }

    out_hash[hash_idx] = '\0';
    return 0;
}

int geohash_decode(const char *hash, double *out_lat, double *out_lon, spatial_bbox_t *out_bbox) {
    if (!hash || !out_lat || !out_lon) return -1;

    size_t len = strlen(hash);
    if (len == 0 || len > GEOHASH_MAX_PRECISION) return -1;

    double lat_min = -90.0, lat_max = 90.0;
    double lon_min = -180.0, lon_max = 180.0;

    bool is_even = true;

    for (size_t i = 0; i < len; i++) {
        uint8_t c = (uint8_t)hash[i];
        int8_t val = BASE32_DECODE_MAP[c];
        if (val < 0) return -1;

        for (int bit = 4; bit >= 0; bit--) {
            int bit_val = (val >> bit) & 1;
            if (is_even) {
                double mid = (lon_min + lon_max) * 0.5;
                if (bit_val) {
                    lon_min = mid;
                } else {
                    lon_max = mid;
                }
            } else {
                double mid = (lat_min + lat_max) * 0.5;
                if (bit_val) {
                    lat_min = mid;
                } else {
                    lat_max = mid;
                }
            }
            is_even = !is_even;
        }
    }

    *out_lat = (lat_min + lat_max) * 0.5;
    *out_lon = (lon_min + lon_max) * 0.5;

    if (out_bbox) {
        out_bbox->min_lat = lat_min;
        out_bbox->min_lon = lon_min;
        out_bbox->max_lat = lat_max;
        out_bbox->max_lon = lon_max;
    }

    return 0;
}

uint64_t geohash_encode_bits(double lat, double lon, uint8_t num_bits) {
    if (num_bits == 0) return 0;
    if (num_bits > 64) num_bits = 64;

    double lat_min = -90.0, lat_max = 90.0;
    double lon_min = -180.0, lon_max = 180.0;

    uint64_t result = 0;
    bool is_even = true;

    for (uint8_t i = 0; i < num_bits; i++) {
        result <<= 1;
        if (is_even) {
            double mid = (lon_min + lon_max) * 0.5;
            if (lon >= mid) {
                result |= 1;
                lon_min = mid;
            } else {
                lon_max = mid;
            }
        } else {
            double mid = (lat_min + lat_max) * 0.5;
            if (lat >= mid) {
                result |= 1;
                lat_min = mid;
            } else {
                lat_max = mid;
            }
        }
        is_even = !is_even;
    }

    return result;
}

void geohash_decode_bits(uint64_t hash_bits, uint8_t num_bits,
                         double *out_lat, double *out_lon, spatial_bbox_t *out_bbox) {
    if (num_bits > 64) num_bits = 64;

    double lat_min = -90.0, lat_max = 90.0;
    double lon_min = -180.0, lon_max = 180.0;

    bool is_even = true;

    for (uint8_t i = 0; i < num_bits; i++) {
        int bit_val = (int)((hash_bits >> (num_bits - 1 - i)) & 1);
        if (is_even) {
            double mid = (lon_min + lon_max) * 0.5;
            if (bit_val) {
                lon_min = mid;
            } else {
                lon_max = mid;
            }
        } else {
            double mid = (lat_min + lat_max) * 0.5;
            if (bit_val) {
                lat_min = mid;
            } else {
                lat_max = mid;
            }
        }
        is_even = !is_even;
    }

    if (out_lat) *out_lat = (lat_min + lat_max) * 0.5;
    if (out_lon) *out_lon = (lon_min + lon_max) * 0.5;

    if (out_bbox) {
        out_bbox->min_lat = lat_min;
        out_bbox->min_lon = lon_min;
        out_bbox->max_lat = lat_max;
        out_bbox->max_lon = lon_max;
    }
}

int geohash_get_neighbor(const char *hash, geohash_direction_t dir, char *out_neighbor) {
    if (!hash || !out_neighbor) return -1;
    size_t len = strlen(hash);
    if (len == 0 || len > GEOHASH_MAX_PRECISION) return -1;

    double lat, lon;
    spatial_bbox_t bbox;
    if (geohash_decode(hash, &lat, &lon, &bbox) != 0) return -1;

    double dlat = bbox.max_lat - bbox.min_lat;
    double dlon = bbox.max_lon - bbox.min_lon;

    double target_lat = lat;
    double target_lon = lon;

    switch (dir) {
        case GEOHASH_DIR_NORTH:
            target_lat = lat + dlat;
            break;
        case GEOHASH_DIR_SOUTH:
            target_lat = lat - dlat;
            break;
        case GEOHASH_DIR_EAST:
            target_lon = lon + dlon;
            break;
        case GEOHASH_DIR_WEST:
            target_lon = lon - dlon;
            break;
    }

    /* Wrap longitude */
    while (target_lon > 180.0) target_lon -= 360.0;
    while (target_lon < -180.0) target_lon += 360.0;

    /* Clamp latitude to [-90, 90] */
    if (target_lat > 90.0) target_lat = 90.0;
    if (target_lat < -90.0) target_lat = -90.0;

    return geohash_encode(target_lat, target_lon, len, out_neighbor);
}

int geohash_get_neighbors(const char *hash, geohash_neighbors_t *out_neighbors) {
    if (!hash || !out_neighbors) return -1;
    size_t len = strlen(hash);
    if (len == 0 || len > GEOHASH_MAX_PRECISION) return -1;

    double lat, lon;
    spatial_bbox_t bbox;
    if (geohash_decode(hash, &lat, &lon, &bbox) != 0) return -1;

    double dlat = bbox.max_lat - bbox.min_lat;
    double dlon = bbox.max_lon - bbox.min_lon;

    double n_lat = fmin(90.0, lat + dlat);
    double s_lat = fmax(-90.0, lat - dlat);

    double e_lon = lon + dlon;
    if (e_lon > 180.0) e_lon -= 360.0;
    double w_lon = lon - dlon;
    if (w_lon < -180.0) w_lon += 360.0;

    geohash_encode(n_lat, lon, len, out_neighbors->north);
    geohash_encode(s_lat, lon, len, out_neighbors->south);
    geohash_encode(lat, e_lon, len, out_neighbors->east);
    geohash_encode(lat, w_lon, len, out_neighbors->west);

    geohash_encode(n_lat, e_lon, len, out_neighbors->north_east);
    geohash_encode(n_lat, w_lon, len, out_neighbors->north_west);
    geohash_encode(s_lat, e_lon, len, out_neighbors->south_east);
    geohash_encode(s_lat, w_lon, len, out_neighbors->south_west);

    return 0;
}

void geohash_cell_dimensions(size_t precision, double *out_lat_deg, double *out_lon_deg) {
    if (precision == 0) precision = 1;
    if (precision > GEOHASH_MAX_PRECISION) precision = GEOHASH_MAX_PRECISION;

    /* Total bits = precision * 5 */
    size_t total_bits = precision * 5;
    size_t lon_bits = (total_bits + 1) / 2;
    size_t lat_bits = total_bits / 2;

    if (out_lat_deg) *out_lat_deg = 180.0 / (double)(1ULL << lat_bits);
    if (out_lon_deg) *out_lon_deg = 360.0 / (double)(1ULL << lon_bits);
}

size_t geohash_optimal_precision(const spatial_bbox_t *bbox) {
    if (!bbox) return 5;
    double dlat = fabs(bbox->max_lat - bbox->min_lat);
    double dlon = fabs(bbox->max_lon - bbox->min_lon);

    for (size_t p = 1; p <= GEOHASH_MAX_PRECISION; p++) {
        double clat, clon;
        geohash_cell_dimensions(p, &clat, &clon);
        if (clat <= dlat || clon <= dlon) {
            return (p > 1) ? (p - 1) : 1;
        }
    }
    return GEOHASH_MAX_PRECISION;
}

size_t geohash_common_prefix_length(const char *hash1, const char *hash2) {
    if (!hash1 || !hash2) return 0;
    size_t len = 0;
    while (hash1[len] && hash2[len] && hash1[len] == hash2[len]) {
        len++;
    }
    return len;
}

char **geohash_cover_bbox(const spatial_bbox_t *bbox, size_t precision, size_t *out_count) {
    if (!bbox || !out_count || precision == 0 || precision > GEOHASH_MAX_PRECISION) {
        if (out_count) *out_count = 0;
        return NULL;
    }

    double clat, clon;
    geohash_cell_dimensions(precision, &clat, &clon);

    double min_lat = fmax(-90.0, bbox->min_lat);
    double max_lat = fmin(90.0, bbox->max_lat);
    double min_lon = fmax(-180.0, bbox->min_lon);
    double max_lon = fmin(180.0, bbox->max_lon);

    size_t cap = 32;
    size_t count = 0;
    char **result = (char **)malloc(cap * sizeof(char *));

    double step_lat = clat * 0.8;
    double step_lon = clon * 0.8;

    for (double cur_lat = min_lat; cur_lat <= max_lat + step_lat * 0.5; cur_lat += step_lat) {
        for (double cur_lon = min_lon; cur_lon <= max_lon + step_lon * 0.5; cur_lon += step_lon) {
            char buf[GEOHASH_MAX_PRECISION + 1];
            if (geohash_encode(fmin(90.0, cur_lat), fmin(180.0, cur_lon), precision, buf) == 0) {
                /* Check if duplicate */
                bool exists = false;
                for (size_t k = 0; k < count; k++) {
                    if (strcmp(result[k], buf) == 0) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    if (count >= cap) {
                        cap *= 2;
                        result = (char **)realloc(result, cap * sizeof(char *));
                    }
                    result[count] = strdup(buf);
                    count++;
                }
            }
        }
    }

    *out_count = count;
    return result;
}
