/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: index/lsm/spatial_lsm.c
 *
 * SkipList MemTable, Bloom filter, and range query implementation
 * for high-throughput spatiotemporal streaming ingestion.
 */

#include "spatial_lsm.h"
#include "../hilbert/hilbert.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Bloom filter hash helpers */
static void bloom_add(convect_lsm_bloom_t *bloom, uint64_t key) {
    uint32_t h1 = (uint32_t)(key ^ (key >> 32));
    uint32_t h2 = (uint32_t)((key * 0xc6a4a7935bd1e995ULL) >> 32);

    for (int i = 0; i < 3; i++) {
        uint32_t bit = (h1 + i * h2) % CONVECT_LSM_BLOOM_BITS;
        bloom->bitset[bit / 8] |= (1 << (bit % 8));
    }
}

static bool bloom_check(const convect_lsm_bloom_t *bloom, uint64_t key) {
    uint32_t h1 = (uint32_t)(key ^ (key >> 32));
    uint32_t h2 = (uint32_t)((key * 0xc6a4a7935bd1e995ULL) >> 32);

    for (int i = 0; i < 3; i++) {
        uint32_t bit = (h1 + i * h2) % CONVECT_LSM_BLOOM_BITS;
        if (!(bloom->bitset[bit / 8] & (1 << (bit % 8)))) {
            return false;
        }
    }
    return true;
}

static int random_level(void) {
    int lvl = 1;
    while ((rand() & 1) && lvl < CONVECT_LSM_SKIPLIST_MAX_LEVEL) {
        lvl++;
    }
    return lvl;
}

static convect_lsm_node_t *node_create(int height, const convect_spatial_record_t *record) {
    convect_lsm_node_t *node = (convect_lsm_node_t *)calloc(1, sizeof(convect_lsm_node_t));
    if (!node) return NULL;
    node->height = height;
    if (record) {
        node->record = *record;
    }
    return node;
}

convect_lsm_memtable_t *convect_lsm_memtable_create(size_t capacity) {
    convect_lsm_memtable_t *mem = (convect_lsm_memtable_t *)calloc(1, sizeof(convect_lsm_memtable_t));
    if (!mem) return NULL;

    mem->capacity = capacity;
    mem->size = 0;
    mem->max_level = 1;
    mem->header = node_create(CONVECT_LSM_SKIPLIST_MAX_LEVEL, NULL);
    if (!mem->header) {
        free(mem);
        return NULL;
    }
    memset(&mem->bloom, 0, sizeof(mem->bloom));
    return mem;
}

void convect_lsm_memtable_free(convect_lsm_memtable_t *mem) {
    if (!mem) return;

    convect_lsm_node_t *curr = mem->header;
    while (curr) {
        convect_lsm_node_t *next = curr->forward[0];
        free(curr);
        curr = next;
    }
    free(mem);
}

uint64_t convect_lsm_make_key(double lat, double lon, int64_t timestamp_ms) {
    /* 24-bit per dimension Hilbert coordinate -> 48-bit code */
    uint64_t hcode = hilbert_from_latlon(lat, lon, 24);
    uint64_t time_suffix = (uint64_t)((timestamp_ms / 1000) & 0xFFFFL);
    return (hcode << 16) | time_suffix;
}

bool convect_lsm_memtable_put(convect_lsm_memtable_t *mem, const convect_spatial_record_t *record) {
    if (!mem || !record) return false;
    if (mem->size >= mem->capacity) return false;

    convect_lsm_node_t *update[CONVECT_LSM_SKIPLIST_MAX_LEVEL];
    convect_lsm_node_t *curr = mem->header;

    for (int i = mem->max_level - 1; i >= 0; i--) {
        while (curr->forward[i] && curr->forward[i]->record.spatial_key < record->spatial_key) {
            curr = curr->forward[i];
        }
        update[i] = curr;
    }

    curr = curr->forward[0];

    /* If key exists, update value and sensor_id */
    if (curr && curr->record.spatial_key == record->spatial_key) {
        curr->record = *record;
        return true;
    }

    /* Otherwise, insert new node */
    int lvl = random_level();
    if (lvl > mem->max_level) {
        for (int i = mem->max_level; i < lvl; i++) {
            update[i] = mem->header;
        }
        mem->max_level = lvl;
    }

    convect_lsm_node_t *new_node = node_create(lvl, record);
    if (!new_node) return false;

    for (int i = 0; i < lvl; i++) {
        new_node->forward[i] = update[i]->forward[i];
        update[i]->forward[i] = new_node;
    }

    mem->size++;
    bloom_add(&mem->bloom, record->spatial_key);
    return true;
}

bool convect_lsm_memtable_get(const convect_lsm_memtable_t *mem, uint64_t spatial_key, convect_spatial_record_t *out_record) {
    if (!mem) return false;

    /* Fast Bloom filter rejection */
    if (!bloom_check(&mem->bloom, spatial_key)) {
        return false;
    }

    convect_lsm_node_t *curr = mem->header;
    for (int i = mem->max_level - 1; i >= 0; i--) {
        while (curr->forward[i] && curr->forward[i]->record.spatial_key < spatial_key) {
            curr = curr->forward[i];
        }
    }

    curr = curr->forward[0];
    if (curr && curr->record.spatial_key == spatial_key) {
        if (out_record) {
            *out_record = curr->record;
        }
        return true;
    }
    return false;
}

size_t convect_lsm_memtable_scan(const convect_lsm_memtable_t *mem,
                                uint64_t min_key, uint64_t max_key,
                                convect_spatial_record_t *out_records, size_t max_results) {
    if (!mem || !out_records || max_results == 0) return 0;

    convect_lsm_node_t *curr = mem->header;
    for (int i = mem->max_level - 1; i >= 0; i--) {
        while (curr->forward[i] && curr->forward[i]->record.spatial_key < min_key) {
            curr = curr->forward[i];
        }
    }

    curr = curr->forward[0];
    size_t count = 0;

    while (curr && curr->record.spatial_key <= max_key && count < max_results) {
        out_records[count++] = curr->record;
        curr = curr->forward[0];
    }

    return count;
}
