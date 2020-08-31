/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: index/h3/h3_lite.c
 *
 * Hexagonal discrete global grid system implementation.
 */

#include "h3_lite.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define H3_MODE_INDEX 1ULL
#define H3_MODE_OFFSET 59
#define H3_RES_OFFSET 52
#define H3_BASE_OFFSET 45
#define H3_DIGIT_MASK 0x7ULL

/* Base cell latitude/longitude approximate centers on icosahedron faces */
static const double BASE_CELL_LATS[122] = {
    89.9,  72.0,  72.0,  72.0,  72.0,  72.0,
    36.0,  36.0,  36.0,  36.0,  36.0,  36.0,  36.0,  36.0,  36.0,  36.0,
     0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,
   -36.0, -36.0, -36.0, -36.0, -36.0, -36.0, -36.0, -36.0, -36.0, -36.0,
   -72.0, -72.0, -72.0, -72.0, -72.0, -89.9,
    /* intermediate grid centers */
    60.0,  60.0,  60.0,  60.0,  60.0,  60.0,  60.0,  60.0,  60.0,  60.0,
    45.0,  45.0,  45.0,  45.0,  45.0,  45.0,  45.0,  45.0,  45.0,  45.0,
    20.0,  20.0,  20.0,  20.0,  20.0,  20.0,  20.0,  20.0,  20.0,  20.0,
   -20.0, -20.0, -20.0, -20.0, -20.0, -20.0, -20.0, -20.0, -20.0, -20.0,
   -45.0, -45.0, -45.0, -45.0, -45.0, -45.0, -45.0, -45.0, -45.0, -45.0,
   -60.0, -60.0, -60.0, -60.0, -60.0, -60.0, -60.0, -60.0, -60.0, -60.0,
    10.0,  10.0,  10.0,  10.0,  10.0,  10.0,  10.0,  10.0,  10.0,  10.0,
   -10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0, -10.0
};

static const double BASE_CELL_LONS[122] = {
      0.0, -144.0,  -72.0,    0.0,   72.0,  144.0,
   -162.0, -126.0,  -90.0,  -54.0,  -18.0,   18.0,   54.0,   90.0,  126.0,  162.0,
   -180.0, -144.0, -108.0,  -72.0,  -36.0,    0.0,   36.0,   72.0,  108.0,  144.0,
   -162.0, -126.0,  -90.0,  -54.0,  -18.0,   18.0,   54.0,   90.0,  126.0,  162.0,
   -144.0,  -72.0,    0.0,   72.0,  144.0,    0.0,
    /* intermediate grid centers */
   -150.0, -110.0,  -70.0,  -30.0,   10.0,   50.0,   90.0,  130.0,  170.0,  -10.0,
   -160.0, -120.0,  -80.0,  -40.0,    0.0,   40.0,   80.0,  120.0,  160.0, -20.0,
   -170.0, -135.0, -100.0,  -65.0,  -30.0,    5.0,   40.0,   75.0,  110.0,  145.0,
   -170.0, -135.0, -100.0,  -65.0,  -30.0,    5.0,   40.0,   75.0,  110.0,  145.0,
   -160.0, -120.0,  -80.0,  -40.0,    0.0,   40.0,   80.0,  120.0,  160.0, -20.0,
   -150.0, -110.0,  -70.0,  -30.0,   10.0,   50.0,   90.0,  130.0,  170.0,  -10.0,
   -140.0, -100.0,  -60.0,  -20.0,   20.0,   60.0,  100.0,  140.0,  180.0,  -60.0,
   -140.0, -100.0,  -60.0,  -20.0,   20.0,   60.0,  100.0,  140.0,  180.0,  -60.0
};

convect_h3_index_t convect_h3_from_geo(double lat, double lon, int res) {
    if (res < 0) res = 0;
    if (res > CONVECT_H3_MAX_RES) res = CONVECT_H3_MAX_RES;

    /* Normalize coordinates */
    if (lat > 90.0) lat = 90.0;
    if (lat < -90.0) lat = -90.0;
    while (lon > 180.0) lon -= 360.0;
    while (lon < -180.0) lon += 360.0;

    /* Find nearest base cell */
    int best_base = 0;
    double min_dist_sq = 1.0e20;

    for (int b = 0; b < CONVECT_H3_NUM_BASE_CELLS; b++) {
        double dlat = lat - BASE_CELL_LATS[b];
        double dlon = lon - BASE_CELL_LONS[b];
        double dsq = dlat * dlat + dlon * dlon;
        if (dsq < min_dist_sq) {
            min_dist_sq = dsq;
            best_base = b;
        }
    }

    /* Initialize 64-bit index header */
    convect_h3_index_t h3 = 0;
    h3 |= (H3_MODE_INDEX & 0xFULL) << H3_MODE_OFFSET;
    h3 |= ((uint64_t)res & 0xFULL) << H3_RES_OFFSET;
    h3 |= ((uint64_t)best_base & 0x7FULL) << H3_BASE_OFFSET;

    /* Generate child digits for resolutions 1..res using aperture-7 coordinates */
    double cur_lat = BASE_CELL_LATS[best_base];
    double cur_lon = BASE_CELL_LONS[best_base];
    double scale = 15.0; /* Initial scale */

    for (int r = 1; r <= res; r++) {
        scale /= 2.6457513110645906; /* sqrt(7) aperture scaling */
        double cos_lat = cos(cur_lat * (M_PI / 180.0));
        if (cos_lat < 0.1) cos_lat = 0.1;

        double d_lat = lat - cur_lat;
        double d_lon = (lon - cur_lon) * cos_lat;

        /* Quantize into 7 directions (0 = center, 1..6 = hexagon vertices) */
        int digit = 0;
        double angle = atan2(d_lat, d_lon);
        double dist = sqrt(d_lat * d_lat + d_lon * d_lon);

        if (dist > scale * 0.25) {
            double normalized_angle = angle;
            if (normalized_angle < 0.0) normalized_angle += 2.0 * M_PI;
            digit = 1 + ((int)(normalized_angle / (M_PI / 3.0))) % 6;
        }

        int shift = 45 - (r * 3);
        h3 |= (((uint64_t)digit) & H3_DIGIT_MASK) << shift;

        /* Adjust reference center */
        if (digit > 0) {
            double dir_angle = (digit - 1) * (M_PI / 3.0);
            cur_lat += sin(dir_angle) * scale * 0.7;
            cur_lon += (cos(dir_angle) * scale * 0.7) / cos_lat;
        }
    }

    /* Set remaining unused child digits to 7 (reserved/unused in H3 spec) */
    for (int r = res + 1; r <= CONVECT_H3_MAX_RES; r++) {
        int shift = 45 - (r * 3);
        h3 |= (0x7ULL & H3_DIGIT_MASK) << shift;
    }

    return h3;
}

bool convect_h3_to_geo(convect_h3_index_t h3, double *lat_out, double *lon_out) {
    if (!lat_out || !lon_out) return false;

    int res = convect_h3_get_resolution(h3);
    int base = convect_h3_get_base_cell(h3);

    if (base < 0 || base >= CONVECT_H3_NUM_BASE_CELLS) return false;

    double lat = BASE_CELL_LATS[base];
    double lon = BASE_CELL_LONS[base];
    double scale = 15.0;

    for (int r = 1; r <= res; r++) {
        scale /= 2.6457513110645906;
        double cos_lat = cos(lat * (M_PI / 180.0));
        if (cos_lat < 0.1) cos_lat = 0.1;

        int shift = 45 - (r * 3);
        int digit = (int)((h3 >> shift) & H3_DIGIT_MASK);

        if (digit >= 1 && digit <= 6) {
            double dir_angle = (digit - 1) * (M_PI / 3.0);
            lat += sin(dir_angle) * scale * 0.7;
            lon += (cos(dir_angle) * scale * 0.7) / cos_lat;
        }
    }

    *lat_out = lat;
    *lon_out = lon;
    return true;
}

int convect_h3_get_resolution(convect_h3_index_t h3) {
    return (int)((h3 >> H3_RES_OFFSET) & 0xFULL);
}

int convect_h3_get_base_cell(convect_h3_index_t h3) {
    return (int)((h3 >> H3_BASE_OFFSET) & 0x7FULL);
}

convect_h3_index_t convect_h3_to_parent(convect_h3_index_t h3, int parent_res) {
    int cur_res = convect_h3_get_resolution(h3);
    if (parent_res >= cur_res) return h3;
    if (parent_res < 0) parent_res = 0;

    /* Update resolution bits */
    convect_h3_index_t parent = h3 & ~(0xFULL << H3_RES_OFFSET);
    parent |= ((uint64_t)parent_res & 0xFULL) << H3_RES_OFFSET;

    /* Mask out digits beyond parent_res with 7 */
    for (int r = parent_res + 1; r <= CONVECT_H3_MAX_RES; r++) {
        int shift = 45 - (r * 3);
        parent &= ~(H3_DIGIT_MASK << shift);
        parent |= (0x7ULL & H3_DIGIT_MASK) << shift;
    }

    return parent;
}

int convect_h3_get_neighbors(convect_h3_index_t h3, convect_h3_index_t *neighbors) {
    if (!neighbors) return 0;

    int res = convect_h3_get_resolution(h3);
    if (res == 0) {
        /* Base cell neighbor fallback */
        int base = convect_h3_get_base_cell(h3);
        for (int i = 0; i < 6; i++) {
            int n_base = (base + i + 1) % CONVECT_H3_NUM_BASE_CELLS;
            convect_h3_index_t n_idx = 0;
            n_idx |= (H3_MODE_INDEX & 0xFULL) << H3_MODE_OFFSET;
            n_idx |= ((uint64_t)n_base & 0x7FULL) << H3_BASE_OFFSET;
            for (int r = 1; r <= CONVECT_H3_MAX_RES; r++) {
                n_idx |= (0x7ULL) << (45 - (r * 3));
            }
            neighbors[i] = n_idx;
        }
        return 6;
    }

    int last_shift = 45 - (res * 3);
    int current_digit = (int)((h3 >> last_shift) & H3_DIGIT_MASK);

    int count = 0;
    for (int d = 1; d <= 6; d++) {
        if (d != current_digit) {
            convect_h3_index_t n_idx = h3 & ~(H3_DIGIT_MASK << last_shift);
            n_idx |= (((uint64_t)d) & H3_DIGIT_MASK) << last_shift;
            neighbors[count++] = n_idx;
        } else {
            /* Center or opposite digit */
            convect_h3_index_t n_idx = h3 & ~(H3_DIGIT_MASK << last_shift);
            n_idx |= (0x0ULL & H3_DIGIT_MASK) << last_shift;
            neighbors[count++] = n_idx;
        }
    }
    return count;
}

int convect_h3_k_ring(convect_h3_index_t origin, int k, convect_h3_index_t *out_cells, int max_capacity) {
    if (!out_cells || max_capacity <= 0) return 0;
    if (k < 0) return 0;

    out_cells[0] = origin;
    int count = 1;

    if (k == 0) return 1;

    convect_h3_index_t immediate[6];
    int n_count = convect_h3_get_neighbors(origin, immediate);

    for (int i = 0; i < n_count && count < max_capacity; i++) {
        out_cells[count++] = immediate[i];
    }

    /* Expand rings for k >= 2 */
    for (int step = 2; step <= k; step++) {
        int ring_start = count - n_count;
        int ring_end = count;
        for (int idx = ring_start; idx < ring_end; idx++) {
            convect_h3_index_t sub_nbrs[6];
            int sub_count = convect_h3_get_neighbors(out_cells[idx], sub_nbrs);
            for (int s = 0; s < sub_count && count < max_capacity; s++) {
                /* Check if already present */
                bool exists = false;
                for (int c = 0; c < count; c++) {
                    if (out_cells[c] == sub_nbrs[s]) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    out_cells[count++] = sub_nbrs[s];
                }
            }
        }
    }

    return count;
}

void convect_h3_to_string(convect_h3_index_t h3, char *buf, size_t buf_len) {
    if (!buf || buf_len < 16) return;
    snprintf(buf, buf_len, "%016llx", (unsigned long long)h3);
}

convect_h3_index_t convect_h3_from_string(const char *str) {
    if (!str) return CONVECT_H3_NULL;
    unsigned long long val = 0;
    if (sscanf(str, "%llx", &val) != 1) {
        return CONVECT_H3_NULL;
    }
    return (convect_h3_index_t)val;
}
