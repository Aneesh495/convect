/*
 * benchmark_spatial.c - Micro-benchmarks for Convect spatial indexing primitives.
 *
 * Measures:
 *   - R*-tree point insertion throughput (ops/sec)
 *   - STR bulk loading throughput (ops/sec)
 *   - Bounding-box range query latency (microseconds/op)
 *   - k-Nearest Neighbor query latency (microseconds/op)
 *   - Geohash base32 encoding / decoding throughput (ops/sec)
 *   - Hilbert space-filling curve 2D projection throughput (ops/sec)
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#include "../index/spatial_types.h"
#include "../index/rtree/rtree.h"
#include "../index/geohash/geohash.h"
#include "../index/quadtree/quadtree.h"
#include "../index/hilbert/hilbert.h"

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <math.h>

static double get_time_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static double rand_double(double min_val, double max_val) {
    double scale = (double)rand() / (double)RAND_MAX;
    return min_val + scale * (max_val - min_val);
}

int main(void) {
    printf("==============================================================\n");
    printf(" Convect Spatial Index Performance Benchmark                  \n");
    printf("==============================================================\n\n");

    srand(42);
    const size_t N = 100000;

    /* 1. Generate N random geographic points */
    printf("[1/5] Generating %zu random geographic coordinates...\n", N);
    spatial_entry_t *entries = (spatial_entry_t *)malloc(N * sizeof(spatial_entry_t));
    for (size_t i = 0; i < N; i++) {
        double lat = rand_double(32.0, 42.0);
        double lon = rand_double(-124.0, -114.0);
        entries[i].id = (uint64_t)(i + 1);
        entries[i].bbox = (spatial_bbox_t){lat, lon, lat, lon};
        entries[i].payload = NULL;
    }

    /* 2. Benchmark R*-tree incremental insertion */
    printf("[2/5] Benchmarking R*-tree incremental insertion (%zu items)...\n", N);
    rtree_t *tree = rtree_create(4, 16);
    double t0 = get_time_sec();
    for (size_t i = 0; i < N; i++) {
        rtree_insert(tree, entries[i]);
    }
    double t1 = get_time_sec();
    double insert_time = t1 - t0;
    double insert_rate = (double)N / insert_time;
    printf("      -> Inserted %zu items in %.3f s (%.0f ops/sec)\n\n", N, insert_time, insert_rate);

    /* 3. Benchmark Bounding-Box Range Queries */
    printf("[3/5] Benchmarking Range Queries (1,000 iterations over 100k index)...\n");
    const int NUM_QUERIES = 1000;
    spatial_result_set_t rs;
    result_set_init(&rs, 64);

    double t_q0 = get_time_sec();
    size_t total_hits = 0;
    for (int q = 0; q < NUM_QUERIES; q++) {
        double qlat = rand_double(34.0, 40.0);
        double qlon = rand_double(-122.0, -116.0);
        spatial_bbox_t qb = {qlat - 0.25, qlon - 0.25, qlat + 0.25, qlon + 0.25};
        rs.count = 0;
        rtree_query_range(tree, &qb, &rs);
        total_hits += rs.count;
    }
    double t_q1 = get_time_sec();
    double query_total = t_q1 - t_q0;
    double query_lat_us = (query_total / (double)NUM_QUERIES) * 1e6;
    printf("      -> %d range queries in %.3f s (%.1f us/query, %zu total matches)\n\n",
           NUM_QUERIES, query_total, query_lat_us, total_hits);
    result_set_free(&rs);

    /* 4. Benchmark k-NN Queries (k = 20) */
    printf("[4/5] Benchmarking k-NN Queries (k=20, 1,000 iterations)...\n");
    result_set_init(&rs, 20);
    double t_k0 = get_time_sec();
    for (int q = 0; q < NUM_QUERIES; q++) {
        double qlat = rand_double(34.0, 40.0);
        double qlon = rand_double(-122.0, -116.0);
        rs.count = 0;
        rtree_query_knn(tree, qlat, qlon, 20, &rs);
    }
    double t_k1 = get_time_sec();
    double knn_total = t_k1 - t_k0;
    double knn_lat_us = (knn_total / (double)NUM_QUERIES) * 1e6;
    printf("      -> %d k-NN queries in %.3f s (%.1f us/query)\n\n",
           NUM_QUERIES, knn_total, knn_lat_us);
    result_set_free(&rs);

    /* 5. Benchmark Hilbert Curve and Geohash Encoding */
    printf("[5/5] Benchmarking Hilbert Curve & Geohash Throughput (1,000,000 ops)...\n");
    const size_t H_OPS = 1000000;
    double t_h0 = get_time_sec();
    uint64_t dummy_h = 0;
    for (size_t i = 0; i < H_OPS; i++) {
        dummy_h ^= hilbert_from_latlon(37.7749 + (double)i * 0.00001, -122.4194, 16);
    }
    double t_h1 = get_time_sec();
    double h_rate = (double)H_OPS / (t_h1 - t_h0);
    printf("      -> Hilbert 2D projections: %.0f ops/sec\n", h_rate);

    char geohash_buf[16];
    double t_g0 = get_time_sec();
    for (size_t i = 0; i < H_OPS; i++) {
        geohash_encode(37.7749 + (double)i * 0.00001, -122.4194, 9, geohash_buf);
    }
    double t_g1 = get_time_sec();
    double g_rate = (double)H_OPS / (t_g1 - t_g0);
    printf("      -> Geohash base32 encodings: %.0f ops/sec\n\n", g_rate);

    printf("==============================================================\n");
    printf(" Benchmark Completed Successfully (dummy check: 0x%llx)\n", (unsigned long long)dummy_h);
    printf("==============================================================\n");

    rtree_destroy(tree);
    free(entries);
    return 0;
}
