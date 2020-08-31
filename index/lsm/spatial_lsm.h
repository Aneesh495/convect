/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: index/lsm/spatial_lsm.h
 *
 * Spatiotemporal Log-Structured Merge (LSM) Tree engine.
 * High-throughput append-only spatial streaming storage with SkipList
 * MemTable, Bloom filters, and Hilbert-temporal compound key range queries.
 */

#ifndef CONVECT_SPATIAL_LSM_H
#define CONVECT_SPATIAL_LSM_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "../spatial_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define CONVECT_LSM_SKIPLIST_MAX_LEVEL 16
#define CONVECT_LSM_BLOOM_BITS 4096

/* Spatiotemporal Record holding compound key, coordinates, and double payload */
typedef struct {
    uint64_t spatial_key;   /* 48-bit Hilbert code << 16 | 16-bit time delta */
    int64_t timestamp_ms;
    double lat;
    double lon;
    double value;
    char sensor_id[32];
} convect_spatial_record_t;

/* SkipList Node */
typedef struct convect_lsm_node {
    convect_spatial_record_t record;
    int height;
    struct convect_lsm_node *forward[CONVECT_LSM_SKIPLIST_MAX_LEVEL];
} convect_lsm_node_t;

/* Bloom Filter */
typedef struct {
    uint8_t bitset[CONVECT_LSM_BLOOM_BITS / 8];
} convect_lsm_bloom_t;

/* Spatial LSM MemTable */
typedef struct {
    convect_lsm_node_t *header;
    size_t size;
    size_t capacity;
    int max_level;
    convect_lsm_bloom_t bloom;
} convect_lsm_memtable_t;

/**
 * Create a new spatiotemporal MemTable with specified capacity.
 */
convect_lsm_memtable_t *convect_lsm_memtable_create(size_t capacity);

/**
 * Destroy MemTable and free all nodes.
 */
void convect_lsm_memtable_free(convect_lsm_memtable_t *mem);

/**
 * Insert a spatiotemporal record into the MemTable.
 * Returns true on success, false if capacity exceeded.
 */
bool convect_lsm_memtable_put(convect_lsm_memtable_t *mem, const convect_spatial_record_t *record);

/**
 * Point lookup by exact compound spatial key.
 */
bool convect_lsm_memtable_get(const convect_lsm_memtable_t *mem, uint64_t spatial_key, convect_spatial_record_t *out_record);

/**
 * Range scan for records within compound key interval [min_key, max_key].
 * Populates out_records up to max_results. Returns actual number of matched records.
 */
size_t convect_lsm_memtable_scan(const convect_lsm_memtable_t *mem,
                                uint64_t min_key, uint64_t max_key,
                                convect_spatial_record_t *out_records, size_t max_results);

/**
 * Compute compound 64-bit spatial key from coordinates and timestamp.
 */
uint64_t convect_lsm_make_key(double lat, double lon, int64_t timestamp_ms);

#ifdef __cplusplus
}
#endif

#endif /* CONVECT_SPATIAL_LSM_H */
