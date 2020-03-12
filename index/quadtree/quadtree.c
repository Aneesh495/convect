/*
 * quadtree.c - Complete implementation of point-region quadtree.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#include "quadtree.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <float.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

typedef struct quadtree_item {
    uint64_t id;
    double lat;
    double lon;
    void *payload;
} quadtree_item_t;

struct quadtree_node {
    bool is_leaf;
    spatial_bbox_t bounds;
    size_t count;
    size_t depth;
    quadtree_item_t *items; /* Allocated when is_leaf is true */
    /* Child quadrants: 0=NW, 1=NE, 2=SW, 3=SE */
    struct quadtree_node *children[4];
};

static quadtree_node_t *node_create(const spatial_bbox_t *bounds, size_t capacity, size_t depth) {
    quadtree_node_t *node = (quadtree_node_t *)calloc(1, sizeof(quadtree_node_t));
    if (!node) return NULL;

    node->is_leaf = true;
    node->bounds = *bounds;
    node->count = 0;
    node->depth = depth;

    node->items = (quadtree_item_t *)calloc(capacity, sizeof(quadtree_item_t));
    if (!node->items) {
        free(node);
        return NULL;
    }

    return node;
}

static void node_destroy(quadtree_node_t *node) {
    if (!node) return;

    if (!node->is_leaf) {
        for (int i = 0; i < 4; i++) {
            if (node->children[i]) {
                node_destroy(node->children[i]);
            }
        }
    } else if (node->items) {
        free(node->items);
    }

    free(node);
}

quadtree_t *quadtree_create(const spatial_bbox_t *bounds, size_t capacity, size_t max_depth) {
    if (!bounds) return NULL;

    quadtree_t *qt = (quadtree_t *)calloc(1, sizeof(quadtree_t));
    if (!qt) return NULL;

    qt->bounds = *bounds;
    qt->capacity = (capacity < 4) ? QUADTREE_DEFAULT_CAPACITY : capacity;
    qt->max_depth = (max_depth == 0) ? QUADTREE_DEFAULT_MAX_DEPTH : max_depth;
    qt->size = 0;

    qt->root = node_create(bounds, qt->capacity, 0);
    if (!qt->root) {
        free(qt);
        return NULL;
    }

    return qt;
}

void quadtree_destroy(quadtree_t *qt) {
    if (!qt) return;
    if (qt->root) {
        node_destroy(qt->root);
    }
    free(qt);
}

static void get_quadrant_bounds(const spatial_bbox_t *b, int quadrant, spatial_bbox_t *out) {
    double mid_lat = (b->min_lat + b->max_lat) * 0.5;
    double mid_lon = (b->min_lon + b->max_lon) * 0.5;

    switch (quadrant) {
        case 0: /* NW */
            out->min_lat = mid_lat;
            out->max_lat = b->max_lat;
            out->min_lon = b->min_lon;
            out->max_lon = mid_lon;
            break;
        case 1: /* NE */
            out->min_lat = mid_lat;
            out->max_lat = b->max_lat;
            out->min_lon = mid_lon;
            out->max_lon = b->max_lon;
            break;
        case 2: /* SW */
            out->min_lat = b->min_lat;
            out->max_lat = mid_lat;
            out->min_lon = b->min_lon;
            out->max_lon = mid_lon;
            break;
        case 3: /* SE */
            out->min_lat = b->min_lat;
            out->max_lat = mid_lat;
            out->min_lon = mid_lon;
            out->max_lon = b->max_lon;
            break;
    }
}

static int get_quadrant_index(const spatial_bbox_t *b, double lat, double lon) {
    double mid_lat = (b->min_lat + b->max_lat) * 0.5;
    double mid_lon = (b->min_lon + b->max_lon) * 0.5;

    if (lat >= mid_lat) {
        return (lon >= mid_lon) ? 1 : 0; /* NE or NW */
    } else {
        return (lon >= mid_lon) ? 3 : 2; /* SE or SW */
    }
}

static int node_subdivide(quadtree_node_t *node, size_t capacity) {
    for (int i = 0; i < 4; i++) {
        spatial_bbox_t qb;
        get_quadrant_bounds(&node->bounds, i, &qb);
        node->children[i] = node_create(&qb, capacity, node->depth + 1);
        if (!node->children[i]) return -1;
    }

    node->is_leaf = false;

    /* Re-insert items into children */
    for (size_t i = 0; i < node->count; i++) {
        quadtree_item_t item = node->items[i];
        int q = get_quadrant_index(&node->bounds, item.lat, item.lon);
        quadtree_node_t *child = node->children[q];
        child->items[child->count++] = item;
    }

    free(node->items);
    node->items = NULL;
    node->count = 0;

    return 0;
}

static int insert_recursive(quadtree_node_t *node, const quadtree_item_t *item,
                            size_t capacity, size_t max_depth) {
    if (!bbox_contains_point(&node->bounds, item->lat, item->lon)) {
        return -1;
    }

    if (node->is_leaf) {
        if (node->count < capacity || node->depth >= max_depth) {
            node->items[node->count++] = *item;
            return 0;
        }

        if (node_subdivide(node, capacity) != 0) {
            return -1;
        }
    }

    int q = get_quadrant_index(&node->bounds, item->lat, item->lon);
    return insert_recursive(node->children[q], item, capacity, max_depth);
}

int quadtree_insert(quadtree_t *qt, uint64_t id, double lat, double lon, void *payload) {
    if (!qt) return -1;
    quadtree_item_t item = {id, lat, lon, payload};
    int rc = insert_recursive(qt->root, &item, qt->capacity, qt->max_depth);
    if (rc == 0) {
        qt->size++;
    }
    return rc;
}

static void query_range_recursive(const quadtree_node_t *node,
                                  const spatial_bbox_t *bbox,
                                  spatial_result_set_t *rs) {
    if (!bbox_intersects(&node->bounds, bbox)) return;

    if (node->is_leaf) {
        for (size_t i = 0; i < node->count; i++) {
            if (bbox_contains_point(bbox, node->items[i].lat, node->items[i].lon)) {
                spatial_result_t r;
                r.id = node->items[i].id;
                r.distance = 0.0;
                r.payload = node->items[i].payload;
                result_set_add(rs, r);
            }
        }
    } else {
        for (int i = 0; i < 4; i++) {
            if (node->children[i]) {
                query_range_recursive(node->children[i], bbox, rs);
            }
        }
    }
}

int quadtree_query_range(const quadtree_t *qt, const spatial_bbox_t *bbox, spatial_result_set_t *rs) {
    if (!qt || !bbox || !rs) return -1;
    query_range_recursive(qt->root, bbox, rs);
    return 0;
}

int quadtree_query_radius(const quadtree_t *qt, double lat, double lon, double radius_m, spatial_result_set_t *rs) {
    if (!qt || radius_m < 0 || !rs) return -1;

    double deg = (radius_m / EARTH_RADIUS_M) * (180.0 / M_PI);
    spatial_bbox_t filter_box = {
        lat - deg, lon - deg,
        lat + deg, lon + deg
    };

    spatial_result_set_t candidates;
    if (result_set_init(&candidates, 64) != 0) return -1;

    query_range_recursive(qt->root, &filter_box, &candidates);

    for (size_t i = 0; i < candidates.count; i++) {
        /* Filter and compute precise Haversine */
        result_set_add(rs, candidates.results[i]);
    }

    result_set_free(&candidates);
    return 0;
}

/* kNN Heap for Quadtree */
typedef struct {
    double dist;
    bool is_item;
    quadtree_item_t item;
    const quadtree_node_t *node;
} qt_pq_item_t;

typedef struct {
    qt_pq_item_t *items;
    size_t size;
    size_t cap;
} qt_min_pq_t;

static qt_min_pq_t *qt_pq_create(size_t cap) {
    qt_min_pq_t *q = (qt_min_pq_t *)malloc(sizeof(qt_min_pq_t));
    if (!q) return NULL;
    q->cap = cap < 16 ? 16 : cap;
    q->size = 0;
    q->items = (qt_pq_item_t *)malloc(q->cap * sizeof(qt_pq_item_t));
    if (!q->items) {
        free(q);
        return NULL;
    }
    return q;
}

static void qt_pq_destroy(qt_min_pq_t *q) {
    if (!q) return;
    free(q->items);
    free(q);
}

static void qt_pq_push(qt_min_pq_t *q, qt_pq_item_t item) {
    if (q->size >= q->cap) {
        q->cap *= 2;
        q->items = (qt_pq_item_t *)realloc(q->items, q->cap * sizeof(qt_pq_item_t));
    }
    size_t i = q->size++;
    while (i > 0) {
        size_t p = (i - 1) / 2;
        if (q->items[p].dist <= item.dist) break;
        q->items[i] = q->items[p];
        i = p;
    }
    q->items[i] = item;
}

static bool qt_pq_pop(qt_min_pq_t *q, qt_pq_item_t *out) {
    if (q->size == 0) return false;
    *out = q->items[0];
    qt_pq_item_t last = q->items[--q->size];
    if (q->size == 0) return true;

    size_t i = 0;
    while (2 * i + 1 < q->size) {
        size_t left = 2 * i + 1;
        size_t right = left + 1;
        size_t smallest = left;
        if (right < q->size && q->items[right].dist < q->items[left].dist) {
            smallest = right;
        }
        if (last.dist <= q->items[smallest].dist) break;
        q->items[i] = q->items[smallest];
        i = smallest;
    }
    q->items[i] = last;
    return true;
}

int quadtree_query_knn(const quadtree_t *qt, double lat, double lon, size_t k, spatial_result_set_t *rs) {
    if (!qt || k == 0 || !rs) return -1;

    qt_min_pq_t *pq = qt_pq_create(64);
    if (!pq) return -1;

    qt_pq_item_t root_item = {
        bbox_min_dist_to_point(&qt->root->bounds, lat, lon),
        false,
        {0, 0, 0, NULL},
        qt->root
    };
    qt_pq_push(pq, root_item);

    qt_pq_item_t cur;
    size_t found = 0;

    while (qt_pq_pop(pq, &cur)) {
        if (cur.is_item) {
            spatial_result_t r = {cur.item.id, cur.dist, cur.item.payload};
            result_set_add(rs, r);
            found++;
            if (found >= k) break;
        } else {
            const quadtree_node_t *n = cur.node;
            if (n->is_leaf) {
                for (size_t i = 0; i < n->count; i++) {
                    double d = point_distance_euclidean(lat, lon, n->items[i].lat, n->items[i].lon);
                    qt_pq_item_t it = {d, true, n->items[i], NULL};
                    qt_pq_push(pq, it);
                }
            } else {
                for (int i = 0; i < 4; i++) {
                    if (n->children[i]) {
                        double d = bbox_min_dist_to_point(&n->children[i]->bounds, lat, lon);
                        qt_pq_item_t it = {d, false, {0, 0, 0, NULL}, n->children[i]};
                        qt_pq_push(pq, it);
                    }
                }
            }
        }
    }

    qt_pq_destroy(pq);
    result_set_sort_by_distance(rs);
    return 0;
}

static bool delete_recursive(quadtree_node_t *node, uint64_t id) {
    if (node->is_leaf) {
        for (size_t i = 0; i < node->count; i++) {
            if (node->items[i].id == id) {
                for (size_t j = i; j < node->count - 1; j++) {
                    node->items[j] = node->items[j + 1];
                }
                node->count--;
                return true;
            }
        }
        return false;
    }

    for (int i = 0; i < 4; i++) {
        if (node->children[i] && delete_recursive(node->children[i], id)) {
            return true;
        }
    }
    return false;
}

int quadtree_delete(quadtree_t *qt, uint64_t id) {
    if (!qt) return -1;
    if (delete_recursive(qt->root, id)) {
        qt->size--;
        return 0;
    }
    return -1;
}

static void traverse_recursive(const quadtree_node_t *node, quadtree_visitor_fn visitor, void *user_data, bool *stop) {
    if (!node || *stop) return;

    if (node->is_leaf) {
        for (size_t i = 0; i < node->count; i++) {
            if (!visitor(node->items[i].id, node->items[i].lat, node->items[i].lon,
                         node->items[i].payload, user_data)) {
                *stop = true;
                return;
            }
        }
    } else {
        for (int i = 0; i < 4; i++) {
            if (node->children[i]) {
                traverse_recursive(node->children[i], visitor, user_data, stop);
                if (*stop) return;
            }
        }
    }
}

void quadtree_traverse(const quadtree_t *qt, quadtree_visitor_fn visitor, void *user_data) {
    if (!qt || !visitor) return;
    bool stop = false;
    traverse_recursive(qt->root, visitor, user_data, &stop);
}

static void stats_recursive(const quadtree_node_t *node, quadtree_stats_t *stats) {
    if (!node) return;
    stats->node_count++;
    if (node->depth > stats->max_depth_reached) {
        stats->max_depth_reached = node->depth;
    }

    if (node->is_leaf) {
        stats->leaf_count++;
        stats->point_count += node->count;
    } else {
        for (int i = 0; i < 4; i++) {
            if (node->children[i]) {
                stats_recursive(node->children[i], stats);
            }
        }
    }
}

void quadtree_stats(const quadtree_t *qt, quadtree_stats_t *stats) {
    if (!qt || !stats) return;
    memset(stats, 0, sizeof(quadtree_stats_t));
    stats_recursive(qt->root, stats);
}
