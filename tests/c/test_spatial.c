/*
 * test_spatial.c - Comprehensive test suite for the Convect C spatial indexing engine.
 *
 * Covers:
 *   - Geometric primitives (bounding boxes, intersections, margins, haversine)
 *   - R*-tree spatial index (insertion, split, forced reinsertion, range query, kNN, STR bulk load)
 *   - Geohash (base32 encode/decode, 64-bit binary bitwise operations, 8-neighbors, bbox cover)
 *   - PR-Quadtree (subdivision, range queries, kNN, deletion, traversal)
 *   - Hilbert space-filling curve (grid mapping, geographic projection, bbox range decomposition)
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#include "../../index/spatial_types.h"
#include "../../index/rtree/rtree.h"
#include "../../index/geohash/geohash.h"
#include "../../index/quadtree/quadtree.h"
#include "../../index/hilbert/hilbert.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <assert.h>

static int g_tests_run = 0;
static int g_tests_passed = 0;

#define TEST_ASSERT(cond, msg) do { \
    g_tests_run++; \
    if (cond) { \
        g_tests_passed++; \
    } else { \
        printf("FAILED [%s:%d]: %s\n", __FILE__, __LINE__, msg); \
    } \
} while(0)

/* --------------------------------------------------------------------------
 * Section 1: Spatial Types & Geodesic Tests
 * -------------------------------------------------------------------------- */

static void test_spatial_primitives(void) {
    printf("[1/5] Testing spatial types and geodesic calculations...\n");

    /* Point distance */
    double d_london_paris = point_distance_haversine(51.5074, -0.1278, 48.8566, 2.3522);
    /* London to Paris is ~343 km */
    TEST_ASSERT(d_london_paris > 340000.0 && d_london_paris < 346000.0,
                "London to Paris Haversine distance should be ~343 km");

    /* Antipodal / self distance */
    double d_self = point_distance_haversine(37.7749, -122.4194, 37.7749, -122.4194);
    TEST_ASSERT(d_self < 0.001, "Self distance should be zero");

    /* Bounding box containment */
    spatial_bbox_t box = {37.0, -123.0, 38.0, -122.0};
    TEST_ASSERT(bbox_contains_point(&box, 37.5, -122.5), "Point should be inside bbox");
    TEST_ASSERT(!bbox_contains_point(&box, 36.9, -122.5), "Point below min_lat should be outside");
    TEST_ASSERT(!bbox_contains_point(&box, 37.5, -121.9), "Point above max_lon should be outside");

    /* Bounding box intersection */
    spatial_bbox_t box2 = {37.5, -122.5, 38.5, -121.5};
    TEST_ASSERT(bbox_intersects(&box, &box2), "Overlapping boxes should intersect");

    spatial_bbox_t disjoint = {39.0, -121.0, 40.0, -120.0};
    TEST_ASSERT(!bbox_intersects(&box, &disjoint), "Disjoint boxes should not intersect");

    /* Union and area */
    spatial_bbox_t u = bbox_union(&box, &box2);
    TEST_ASSERT(fabs(u.min_lat - 37.0) < 1e-9 && fabs(u.max_lat - 38.5) < 1e-9, "Union lat bounds");
    TEST_ASSERT(fabs(u.min_lon - -123.0) < 1e-9 && fabs(u.max_lon - -121.5) < 1e-9, "Union lon bounds");

    double a = bbox_area(&box);
    TEST_ASSERT(fabs(a - 1.0) < 1e-9, "Area of 1x1 degree box should be 1.0 deg^2");

    double overlap = bbox_overlap_area(&box, &box2);
    TEST_ASSERT(fabs(overlap - 0.25) < 1e-9, "Overlap area of 0.5x0.5 deg overlap should be 0.25");

    /* Margin */
    double m = bbox_margin(&box);
    TEST_ASSERT(fabs(m - 2.0) < 1e-9, "Margin of 1x1 box should be 2.0");

    /* Result set operations */
    spatial_result_set_t rs;
    result_set_init(&rs, 4);
    for (int i = 0; i < 20; i++) {
        spatial_result_t r = {(uint64_t)i, (double)(20 - i), NULL};
        result_set_add(&rs, r);
    }
    TEST_ASSERT(rs.count == 20, "Result set count should be 20");
    result_set_sort_by_distance(&rs);
    TEST_ASSERT(rs.results[0].distance < rs.results[19].distance, "Result set should be sorted by distance");
    result_set_free(&rs);
}

/* --------------------------------------------------------------------------
 * Section 2: R*-Tree Tests
 * -------------------------------------------------------------------------- */

static void test_rtree(void) {
    printf("[2/5] Testing R*-tree spatial index...\n");

    rtree_t *tree = rtree_create(4, 8);
    TEST_ASSERT(tree != NULL, "rtree_create should succeed");

    /* Insert 100 points across California */
    for (int i = 0; i < 100; i++) {
        double lat = 32.0 + (i % 10) * 0.8;
        double lon = -124.0 + (i / 10) * 0.8;
        int rc = rtree_insert_point(tree, (uint64_t)(i + 1), lat, lon, NULL);
        TEST_ASSERT(rc == 0, "rtree_insert_point should return 0");
    }
    TEST_ASSERT(tree->size == 100, "rtree size should be 100");

    /* Range query */
    spatial_bbox_t qbox = {34.0, -122.0, 36.0, -120.0};
    spatial_result_set_t rs;
    result_set_init(&rs, 16);
    int qrc = rtree_query_range(tree, &qbox, &rs);
    TEST_ASSERT(qrc == 0, "rtree_query_range should succeed");
    TEST_ASSERT(rs.count > 0, "Range query should return points");
    result_set_free(&rs);

    /* k-NN query */
    result_set_init(&rs, 5);
    int knn_rc = rtree_query_knn(tree, 35.0, -121.0, 5, &rs);
    TEST_ASSERT(knn_rc == 0, "rtree_query_knn should succeed");
    TEST_ASSERT(rs.count == 5, "k-NN should return exactly k=5 results");
    for (size_t i = 1; i < rs.count; i++) {
        TEST_ASSERT(rs.results[i].distance >= rs.results[i-1].distance, "k-NN results must be ordered");
    }
    result_set_free(&rs);

    /* Deletion */
    int del_rc = rtree_delete(tree, 1);
    TEST_ASSERT(del_rc == 0, "rtree_delete should succeed for existing ID");
    TEST_ASSERT(tree->size == 99, "rtree size should decrease by 1");

    int del_nonexistent = rtree_delete(tree, 99999);
    TEST_ASSERT(del_nonexistent != 0, "rtree_delete should fail for nonexistent ID");

    /* Stats */
    rtree_stats_t stats;
    rtree_stats(tree, &stats);
    TEST_ASSERT(stats.entry_count == 99, "Stats entry count should match tree size");
    TEST_ASSERT(stats.height >= 2, "Height of 99 items with max=8 should be >= 2");
    TEST_ASSERT(stats.avg_fill > 0.0, "Average fill factor should be positive");

    rtree_destroy(tree);

    /* Bulk loading test */
    const size_t bulk_n = 200;
    spatial_entry_t *bulk_entries = (spatial_entry_t *)malloc(bulk_n * sizeof(spatial_entry_t));
    for (size_t i = 0; i < bulk_n; i++) {
        double lat = 40.0 + (double)(i % 20) * 0.1;
        double lon = -74.0 + (double)(i / 20) * 0.1;
        bulk_entries[i].id = (uint64_t)(i + 1000);
        bulk_entries[i].bbox = (spatial_bbox_t){lat, lon, lat, lon};
        bulk_entries[i].payload = NULL;
    }

    rtree_t *bulk_tree = rtree_bulk_load(bulk_entries, bulk_n, 4, 16);
    TEST_ASSERT(bulk_tree != NULL, "rtree_bulk_load should return tree");
    TEST_ASSERT(bulk_tree->size == bulk_n, "Bulk loaded tree size should match input count");

    spatial_bbox_t ny_box = {40.2, -73.8, 41.0, -73.0};
    result_set_init(&rs, 16);
    rtree_query_range(bulk_tree, &ny_box, &rs);
    TEST_ASSERT(rs.count > 0, "Bulk tree range query should find entries");
    result_set_free(&rs);

    rtree_destroy(bulk_tree);
    free(bulk_entries);
}

/* --------------------------------------------------------------------------
 * Section 3: Geohash Tests
 * -------------------------------------------------------------------------- */

static void test_geohash(void) {
    printf("[3/5] Testing Geohash encoding and topology...\n");

    /* Known geohash test */
    char hash[16];
    int rc = geohash_encode(37.7749, -122.4194, 9, hash);
    TEST_ASSERT(rc == 0, "geohash_encode should succeed");
    TEST_ASSERT(strlen(hash) == 9, "Hash length should match precision");
    TEST_ASSERT(strncmp(hash, "9q8yy", 5) == 0, "San Francisco geohash should start with 9q8yy");

    /* Decode roundtrip */
    double dec_lat, dec_lon;
    spatial_bbox_t cell_box;
    rc = geohash_decode(hash, &dec_lat, &dec_lon, &cell_box);
    TEST_ASSERT(rc == 0, "geohash_decode should succeed");
    TEST_ASSERT(fabs(dec_lat - 37.7749) < 0.001, "Decoded lat should be close to original");
    TEST_ASSERT(fabs(dec_lon - -122.4194) < 0.001, "Decoded lon should be close to original");
    TEST_ASSERT(bbox_contains_point(&cell_box, 37.7749, -122.4194), "Cell box must contain original point");

    /* 64-bit binary geohash roundtrip */
    uint64_t bits = geohash_encode_bits(37.7749, -122.4194, 40);
    double blat, blon;
    geohash_decode_bits(bits, 40, &blat, &blon, NULL);
    TEST_ASSERT(fabs(blat - 37.7749) < 0.001, "Binary geohash lat should roundtrip");
    TEST_ASSERT(fabs(blon - -122.4194) < 0.001, "Binary geohash lon should roundtrip");

    /* 8 Neighbors */
    geohash_neighbors_t nbrs;
    rc = geohash_get_neighbors(hash, &nbrs);
    TEST_ASSERT(rc == 0, "geohash_get_neighbors should succeed");
    TEST_ASSERT(strlen(nbrs.north) == 9, "North neighbor length");
    TEST_ASSERT(strlen(nbrs.south) == 9, "South neighbor length");
    TEST_ASSERT(strlen(nbrs.east) == 9, "East neighbor length");
    TEST_ASSERT(strlen(nbrs.west) == 9, "West neighbor length");
    TEST_ASSERT(strcmp(nbrs.north, hash) != 0, "Neighbor must differ from center");

    /* Common prefix */
    size_t cpl = geohash_common_prefix_length(hash, nbrs.north);
    TEST_ASSERT(cpl >= 4, "Immediate neighbor should share substantial common prefix");

    /* Bbox cover */
    spatial_bbox_t small_box = {37.75, -122.45, 37.80, -122.40};
    size_t cover_count = 0;
    char **cover = geohash_cover_bbox(&small_box, 6, &cover_count);
    TEST_ASSERT(cover != NULL && cover_count > 0, "geohash_cover_bbox should yield cells");
    for (size_t i = 0; i < cover_count; i++) {
        free(cover[i]);
    }
    free(cover);
}

/* --------------------------------------------------------------------------
 * Section 4: Quadtree Tests
 * -------------------------------------------------------------------------- */

static bool count_visitor(uint64_t id, double lat, double lon, void *payload, void *user_data) {
    (void)id; (void)lat; (void)lon; (void)payload;
    size_t *cnt = (size_t *)user_data;
    (*cnt)++;
    return true;
}

static void test_quadtree(void) {
    printf("[4/5] Testing PR-Quadtree index...\n");

    spatial_bbox_t world = {-90.0, -180.0, 90.0, 180.0};
    quadtree_t *qt = quadtree_create(&world, 8, 12);
    TEST_ASSERT(qt != NULL, "quadtree_create should succeed");

    /* Insert 150 points */
    for (int i = 0; i < 150; i++) {
        double lat = -40.0 + (double)i * 0.5;
        double lon = -60.0 + (double)i * 0.8;
        int rc = quadtree_insert(qt, (uint64_t)(i + 1), lat, lon, NULL);
        TEST_ASSERT(rc == 0, "quadtree_insert should succeed");
    }
    TEST_ASSERT(qt->size == 150, "quadtree size should be 150");

    /* Range query */
    spatial_bbox_t qb = {-20.0, -30.0, 10.0, 20.0};
    spatial_result_set_t rs;
    result_set_init(&rs, 32);
    quadtree_query_range(qt, &qb, &rs);
    TEST_ASSERT(rs.count > 0, "Quadtree range query should find points");
    result_set_free(&rs);

    /* k-NN query */
    result_set_init(&rs, 5);
    quadtree_query_knn(qt, 0.0, 0.0, 5, &rs);
    TEST_ASSERT(rs.count == 5, "Quadtree k-NN should return 5 points");
    result_set_free(&rs);

    /* Traversal */
    size_t visited = 0;
    quadtree_traverse(qt, count_visitor, &visited);
    TEST_ASSERT(visited == 150, "Quadtree traversal should visit all 150 points");

    /* Deletion */
    int drc = quadtree_delete(qt, 42);
    TEST_ASSERT(drc == 0, "quadtree_delete should succeed for ID 42");
    TEST_ASSERT(qt->size == 149, "quadtree size should be 149 after delete");

    quadtree_stats_t stats;
    quadtree_stats(qt, &stats);
    TEST_ASSERT(stats.point_count == 149, "Stats point count should match size");
    TEST_ASSERT(stats.node_count > 1, "Subdivision must have occurred");

    quadtree_destroy(qt);
}

/* --------------------------------------------------------------------------
 * Section 5: Hilbert Curve Tests
 * -------------------------------------------------------------------------- */

static void test_hilbert(void) {
    printf("[5/5] Testing Hilbert space-filling curve mapping...\n");

    /* Roundtrip 2D grid coordinates for order 4 */
    uint32_t order = 4;
    uint32_t max_c = (1U << order);
    bool all_roundtrip = true;
    for (uint32_t x = 0; x < max_c; x++) {
        for (uint32_t y = 0; y < max_c; y++) {
            uint64_t d = hilbert_xy_to_d(x, y, order);
            uint32_t rx, ry;
            hilbert_d_to_xy(d, order, &rx, &ry);
            if (rx != x || ry != y) {
                all_roundtrip = false;
                break;
            }
        }
    }
    TEST_ASSERT(all_roundtrip, "Hilbert xy <-> d roundtrip for all points in order 4");

    /* Geographic projection roundtrip */
    double lat = 37.7749;
    double lon = -122.4194;
    uint64_t h = hilbert_from_latlon(lat, lon, 16);
    double rlat, rlon;
    hilbert_to_latlon(h, 16, &rlat, &rlon);
    TEST_ASSERT(fabs(rlat - lat) < 0.05, "Hilbert geographic lat roundtrip within grid cell");
    TEST_ASSERT(fabs(rlon - lon) < 0.05, "Hilbert geographic lon roundtrip within grid cell");

    /* Locality preservation: nearby points should have closer Hilbert indices than distant points */
    uint64_t h_sf1 = hilbert_from_latlon(37.7749, -122.4194, 16);
    uint64_t h_sf2 = hilbert_from_latlon(37.7750, -122.4190, 16);
    uint64_t h_tokyo = hilbert_from_latlon(35.6762, 139.6503, 16);

    uint64_t diff_near = (h_sf1 > h_sf2) ? (h_sf1 - h_sf2) : (h_sf2 - h_sf1);
    uint64_t diff_far = (h_sf1 > h_tokyo) ? (h_sf1 - h_tokyo) : (h_tokyo - h_sf1);
    TEST_ASSERT(diff_near < diff_far, "Hilbert index difference for nearby points must be smaller than distant points");

    /* Hilbert range set merging */
    hilbert_range_set_t rs;
    hilbert_range_set_init(&rs, 4);
    hilbert_range_set_add(&rs, 10, 20);
    hilbert_range_set_add(&rs, 21, 30); /* Contiguous, should merge */
    TEST_ASSERT(rs.count == 1, "Contiguous ranges should merge");
    TEST_ASSERT(rs.ranges[0].start == 10 && rs.ranges[0].end == 30, "Merged range bounds");

    hilbert_range_set_add(&rs, 50, 60);
    TEST_ASSERT(rs.count == 2, "Disjoint range should add new entry");
    hilbert_range_set_free(&rs);

    /* Bounding box decomposition */
    spatial_bbox_t bay_area = {37.0, -123.0, 38.0, -122.0};
    hilbert_range_set_t decomp;
    int drc = hilbert_decompose_bbox(&bay_area, 8, 16, &decomp);
    TEST_ASSERT(drc == 0, "hilbert_decompose_bbox should succeed");
    TEST_ASSERT(decomp.count > 0 && decomp.count <= 16, "Decomposed ranges count within max_ranges");
    hilbert_range_set_free(&decomp);
}

/* --------------------------------------------------------------------------
 * Main Runner
 * -------------------------------------------------------------------------- */

int main(void) {
    printf("====================================================\n");
    printf(" Convect Spatial Indexing Engine - C Test Suite     \n");
    printf("====================================================\n\n");

    test_spatial_primitives();
    test_rtree();
    test_geohash();
    test_quadtree();
    test_hilbert();

    printf("\n----------------------------------------------------\n");
    printf("Tests run: %d | Passed: %d | Failed: %d\n",
           g_tests_run, g_tests_passed, g_tests_run - g_tests_passed);
    printf("----------------------------------------------------\n");

    if (g_tests_run == g_tests_passed) {
        printf("ALL TESTS PASSED.\n\n");
        return 0;
    } else {
        printf("SOME TESTS FAILED.\n\n");
        return 1;
    }
}
