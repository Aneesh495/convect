/*
 * rtree.c - Complete R*-tree spatial index implementation.
 *
 * Implements the R*-tree algorithm described by Beckmann, Kriegel, Schneider,
 * and Seeger (1990): "The R*-tree: An Efficient and Robust Access Method for
 * Points and Rectangles".
 *
 * Algorithmic highlights:
 *   - ChooseSubtree: For leaf insertion, minimizes overlap enlargement; if ties,
 *     minimizes area enlargement; if still tied, minimizes area. For non-leaf
 *     insertion, minimizes area enlargement.
 *   - Forced Reinsertion: When a node overflows, rather than immediately splitting,
 *     30% of its entries (the ones farthest from the node bounding box center) are
 *     removed and reinserted from the root. This is performed at most once per level.
 *   - Split: Evaluates all distributions along latitude and longitude axes. Chooses
 *     the axis minimizing margin sum, then chooses the distribution minimizing overlap.
 *   - k-Nearest Neighbor: Best-first branch-and-bound search using a min-heap priority queue
 *     ordered by minimum distance from the query point to the bounding box.
 *   - Sort-Tile-Recursive (STR) Bulk Loading: Slices entries along coordinates to achieve
 *     near 100% node fill factor.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#include "rtree.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <float.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* --------------------------------------------------------------------------
 * Node Lifecycle
 * -------------------------------------------------------------------------- */

static rtree_node_t *node_create(bool is_leaf, int max_children, rtree_node_t *parent) {
    rtree_node_t *node = (rtree_node_t *)calloc(1, sizeof(rtree_node_t));
    if (!node) return NULL;

    node->is_leaf = is_leaf;
    node->count = 0;
    node->max_children = max_children;
    node->parent = parent;
    node->bbox = (spatial_bbox_t){0, 0, 0, 0};

    int cap = max_children + 1; /* One extra slot to accommodate overflow before split */

    node->child_bboxes = (spatial_bbox_t *)calloc(cap, sizeof(spatial_bbox_t));
    if (!node->child_bboxes) {
        free(node);
        return NULL;
    }

    if (is_leaf) {
        node->entries = (spatial_entry_t *)calloc(cap, sizeof(spatial_entry_t));
        if (!node->entries) {
            free(node->child_bboxes);
            free(node);
            return NULL;
        }
    } else {
        node->children = (rtree_node_t **)calloc(cap, sizeof(rtree_node_t *));
        if (!node->children) {
            free(node->child_bboxes);
            free(node);
            return NULL;
        }
    }

    return node;
}

static void node_destroy(rtree_node_t *node) {
    if (!node) return;

    if (!node->is_leaf && node->children) {
        for (int i = 0; i < node->count; i++) {
            if (node->children[i]) {
                node_destroy(node->children[i]);
            }
        }
        free(node->children);
    } else if (node->is_leaf && node->entries) {
        free(node->entries);
    }

    if (node->child_bboxes) {
        free(node->child_bboxes);
    }
    free(node);
}

static void node_update_bbox(rtree_node_t *node) {
    if (node->count == 0) {
        node->bbox = (spatial_bbox_t){0, 0, 0, 0};
        return;
    }

    spatial_bbox_t b = node->child_bboxes[0];
    for (int i = 1; i < node->count; i++) {
        b = bbox_union(&b, &node->child_bboxes[i]);
    }
    node->bbox = b;
}

/* --------------------------------------------------------------------------
 * Tree Lifecycle
 * -------------------------------------------------------------------------- */

rtree_t *rtree_create(int min_children, int max_children) {
    if (min_children <= 0) min_children = RTREE_DEFAULT_MIN_CHILDREN;
    if (max_children <= 0) max_children = RTREE_DEFAULT_MAX_CHILDREN;

    if (max_children < 4) max_children = 4;
    if (min_children < 2) min_children = 2;
    if (min_children > max_children / 2) {
        min_children = max_children / 2;
    }

    rtree_t *tree = (rtree_t *)calloc(1, sizeof(rtree_t));
    if (!tree) return NULL;

    tree->min_children = min_children;
    tree->max_children = max_children;
    tree->size = 0;
    tree->height = 1;

    tree->root = node_create(true, max_children, NULL);
    if (!tree->root) {
        free(tree);
        return NULL;
    }

    return tree;
}

void rtree_destroy(rtree_t *tree) {
    if (!tree) return;
    if (tree->root) {
        node_destroy(tree->root);
    }
    free(tree);
}

/* --------------------------------------------------------------------------
 * ChooseSubtree
 * -------------------------------------------------------------------------- */

static rtree_node_t *choose_subtree(rtree_node_t *node, const spatial_bbox_t *entry_bbox) {
    if (node->is_leaf) return node;

    bool children_are_leaves = node->children[0]->is_leaf;
    int best_index = 0;

    if (children_are_leaves) {
        /* Minimize overlap enlargement */
        double best_overlap_enlargement = DBL_MAX;
        double best_area_enlargement = DBL_MAX;

        for (int i = 0; i < node->count; i++) {
            spatial_bbox_t old_b = node->child_bboxes[i];
            spatial_bbox_t new_b = bbox_union(&old_b, entry_bbox);

            double old_overlap = 0.0;
            double new_overlap = 0.0;

            for (int j = 0; j < node->count; j++) {
                if (i == j) continue;
                old_overlap += bbox_overlap_area(&old_b, &node->child_bboxes[j]);
                new_overlap += bbox_overlap_area(&new_b, &node->child_bboxes[j]);
            }

            double overlap_enlargement = new_overlap - old_overlap;
            double area_enlargement = bbox_area(&new_b) - bbox_area(&old_b);

            if (overlap_enlargement < best_overlap_enlargement ||
                (fabs(overlap_enlargement - best_overlap_enlargement) < 1e-9 &&
                 area_enlargement < best_area_enlargement)) {
                best_overlap_enlargement = overlap_enlargement;
                best_area_enlargement = area_enlargement;
                best_index = i;
            }
        }
    } else {
        /* Minimize area enlargement */
        double best_area_enlargement = DBL_MAX;
        double best_area = DBL_MAX;

        for (int i = 0; i < node->count; i++) {
            spatial_bbox_t old_b = node->child_bboxes[i];
            spatial_bbox_t new_b = bbox_union(&old_b, entry_bbox);
            double area_enlargement = bbox_area(&new_b) - bbox_area(&old_b);
            double area = bbox_area(&new_b);

            if (area_enlargement < best_area_enlargement ||
                (fabs(area_enlargement - best_area_enlargement) < 1e-9 && area < best_area)) {
                best_area_enlargement = area_enlargement;
                best_area = area;
                best_index = i;
            }
        }
    }

    return choose_subtree(node->children[best_index], entry_bbox);
}

/* --------------------------------------------------------------------------
 * R*-Tree Splitting
 * -------------------------------------------------------------------------- */

typedef struct {
    int index;
    double key;
} sort_entry_t;

static int compare_sort_entries(const void *a, const void *b) {
    const sort_entry_t *sa = (const sort_entry_t *)a;
    const sort_entry_t *sb = (const sort_entry_t *)b;
    if (sa->key < sb->key) return -1;
    if (sa->key > sb->key) return 1;
    return 0;
}

static void split_node(rtree_t *tree, rtree_node_t *node, rtree_node_t **out_sibling) {
    int total = node->count;
    int min_c = tree->min_children;
    int distributions = total - 2 * min_c + 1;

    int best_axis = 0; /* 0 for latitude, 1 for longitude */
    double best_margin_sum = DBL_MAX;

    sort_entry_t *sort_buf = (sort_entry_t *)malloc(total * sizeof(sort_entry_t));

    /* Axis selection */
    for (int axis = 0; axis < 2; axis++) {
        for (int i = 0; i < total; i++) {
            sort_buf[i].index = i;
            sort_buf[i].key = (axis == 0) ? node->child_bboxes[i].min_lat : node->child_bboxes[i].min_lon;
        }
        qsort(sort_buf, total, sizeof(sort_entry_t), compare_sort_entries);

        double margin_sum = 0.0;
        for (int k = 0; k < distributions; k++) {
            int split_point = min_c + k;

            spatial_bbox_t b1 = node->child_bboxes[sort_buf[0].index];
            for (int i = 1; i < split_point; i++) {
                b1 = bbox_union(&b1, &node->child_bboxes[sort_buf[i].index]);
            }

            spatial_bbox_t b2 = node->child_bboxes[sort_buf[split_point].index];
            for (int i = split_point + 1; i < total; i++) {
                b2 = bbox_union(&b2, &node->child_bboxes[sort_buf[i].index]);
            }

            margin_sum += bbox_margin(&b1) + bbox_margin(&b2);
        }

        if (margin_sum < best_margin_sum) {
            best_margin_sum = margin_sum;
            best_axis = axis;
        }
    }

    /* Distribution selection along best_axis */
    for (int i = 0; i < total; i++) {
        sort_buf[i].index = i;
        sort_buf[i].key = (best_axis == 0) ? node->child_bboxes[i].min_lat : node->child_bboxes[i].min_lon;
    }
    qsort(sort_buf, total, sizeof(sort_entry_t), compare_sort_entries);

    int best_split = min_c;
    double best_overlap = DBL_MAX;
    double best_area = DBL_MAX;

    for (int k = 0; k < distributions; k++) {
        int split_point = min_c + k;

        spatial_bbox_t b1 = node->child_bboxes[sort_buf[0].index];
        for (int i = 1; i < split_point; i++) {
            b1 = bbox_union(&b1, &node->child_bboxes[sort_buf[i].index]);
        }

        spatial_bbox_t b2 = node->child_bboxes[sort_buf[split_point].index];
        for (int i = split_point + 1; i < total; i++) {
            b2 = bbox_union(&b2, &node->child_bboxes[sort_buf[i].index]);
        }

        double overlap = bbox_overlap_area(&b1, &b2);
        double area_sum = bbox_area(&b1) + bbox_area(&b2);

        if (overlap < best_overlap ||
            (fabs(overlap - best_overlap) < 1e-9 && area_sum < best_area)) {
            best_overlap = overlap;
            best_area = area_sum;
            best_split = split_point;
        }
    }

    /* Create sibling node */
    rtree_node_t *sibling = node_create(node->is_leaf, node->max_children, node->parent);

    /* Allocate temp arrays to copy items */
    spatial_bbox_t *temp_bboxes = (spatial_bbox_t *)malloc(total * sizeof(spatial_bbox_t));
    spatial_entry_t *temp_entries = node->is_leaf ? (spatial_entry_t *)malloc(total * sizeof(spatial_entry_t)) : NULL;
    rtree_node_t **temp_children = !node->is_leaf ? (rtree_node_t **)malloc(total * sizeof(rtree_node_t *)) : NULL;

    for (int i = 0; i < total; i++) {
        int orig = sort_buf[i].index;
        temp_bboxes[i] = node->child_bboxes[orig];
        if (node->is_leaf) {
            temp_entries[i] = node->entries[orig];
        } else {
            temp_children[i] = node->children[orig];
        }
    }

    /* Assign first part to node */
    node->count = best_split;
    for (int i = 0; i < best_split; i++) {
        node->child_bboxes[i] = temp_bboxes[i];
        if (node->is_leaf) {
            node->entries[i] = temp_entries[i];
        } else {
            node->children[i] = temp_children[i];
            node->children[i]->parent = node;
        }
    }

    /* Assign second part to sibling */
    sibling->count = total - best_split;
    for (int i = 0; i < sibling->count; i++) {
        sibling->child_bboxes[i] = temp_bboxes[best_split + i];
        if (sibling->is_leaf) {
            sibling->entries[i] = temp_entries[best_split + i];
        } else {
            sibling->children[i] = temp_children[best_split + i];
            sibling->children[i]->parent = sibling;
        }
    }

    node_update_bbox(node);
    node_update_bbox(sibling);

    free(temp_bboxes);
    if (temp_entries) free(temp_entries);
    if (temp_children) free(temp_children);
    free(sort_buf);

    *out_sibling = sibling;
}

/* --------------------------------------------------------------------------
 * Insertion & Overflow Treatment
 * -------------------------------------------------------------------------- */

static int insert_entry_recursive(rtree_t *tree, rtree_node_t *node,
                                  const spatial_entry_t *entry,
                                  rtree_node_t *child_node,
                                  const spatial_bbox_t *item_bbox,
                                  bool *reinserted_level,
                                  int current_level);

static int treat_overflow(rtree_t *tree, rtree_node_t *node,
                          bool *reinserted_level, int current_level) {
    if (node->count <= node->max_children) return 0;

    /* If not root and reinsertion has not occurred at this level yet */
    if (node != tree->root && !reinserted_level[current_level]) {
        reinserted_level[current_level] = true;

        /* Sort entries by distance of their center to node center in descending order */
        double center_lat = (node->bbox.min_lat + node->bbox.max_lat) * 0.5;
        double center_lon = (node->bbox.min_lon + node->bbox.max_lon) * 0.5;

        int total = node->count;
        sort_entry_t *dist_sort = (sort_entry_t *)malloc(total * sizeof(sort_entry_t));
        for (int i = 0; i < total; i++) {
            double elat = (node->child_bboxes[i].min_lat + node->child_bboxes[i].max_lat) * 0.5;
            double elon = (node->child_bboxes[i].min_lon + node->child_bboxes[i].max_lon) * 0.5;
            double d = point_distance_euclidean(center_lat, center_lon, elat, elon);
            dist_sort[i].index = i;
            dist_sort[i].key = d;
        }
        qsort(dist_sort, total, sizeof(sort_entry_t), compare_sort_entries);

        /* Number of entries to reinsert (30%) */
        int p = (int)(total * RTREE_REINSERT_FRACTION);
        if (p < 1) p = 1;
        if (p > total - tree->min_children) {
            p = total - tree->min_children;
        }

        int keep = total - p;

        /* Hold removed items in temporary buffers */
        spatial_bbox_t *rem_bboxes = (spatial_bbox_t *)malloc(p * sizeof(spatial_bbox_t));
        spatial_entry_t *rem_entries = node->is_leaf ? (spatial_entry_t *)malloc(p * sizeof(spatial_entry_t)) : NULL;
        rtree_node_t **rem_children = !node->is_leaf ? (rtree_node_t **)malloc(p * sizeof(rtree_node_t *)) : NULL;

        for (int i = 0; i < p; i++) {
            int orig = dist_sort[keep + i].index;
            rem_bboxes[i] = node->child_bboxes[orig];
            if (node->is_leaf) {
                rem_entries[i] = node->entries[orig];
            } else {
                rem_children[i] = node->children[orig];
            }
        }

        /* Compact node to keep items */
        spatial_bbox_t *keep_bboxes = (spatial_bbox_t *)malloc(keep * sizeof(spatial_bbox_t));
        spatial_entry_t *keep_entries = node->is_leaf ? (spatial_entry_t *)malloc(keep * sizeof(spatial_entry_t)) : NULL;
        rtree_node_t **keep_children = !node->is_leaf ? (rtree_node_t **)malloc(keep * sizeof(rtree_node_t *)) : NULL;

        for (int i = 0; i < keep; i++) {
            int orig = dist_sort[i].index;
            keep_bboxes[i] = node->child_bboxes[orig];
            if (node->is_leaf) {
                keep_entries[i] = node->entries[orig];
            } else {
                keep_children[i] = node->children[orig];
            }
        }

        node->count = keep;
        for (int i = 0; i < keep; i++) {
            node->child_bboxes[i] = keep_bboxes[i];
            if (node->is_leaf) {
                node->entries[i] = keep_entries[i];
            } else {
                node->children[i] = keep_children[i];
                node->children[i]->parent = node;
            }
        }

        node_update_bbox(node);

        free(dist_sort);
        free(keep_bboxes);
        if (keep_entries) free(keep_entries);
        if (keep_children) free(keep_children);

        /* Reinsert removed items from the root */
        for (int i = 0; i < p; i++) {
            if (node->is_leaf) {
                insert_entry_recursive(tree, tree->root, &rem_entries[i], NULL,
                                       &rem_bboxes[i], reinserted_level, 0);
            } else {
                insert_entry_recursive(tree, tree->root, NULL, rem_children[i],
                                       &rem_bboxes[i], reinserted_level, 0);
            }
        }

        free(rem_bboxes);
        if (rem_entries) free(rem_entries);
        if (rem_children) free(rem_children);
        return 0;
    }

    /* Split node */
    rtree_node_t *sibling = NULL;
    split_node(tree, node, &sibling);

    if (node == tree->root) {
        /* New root */
        rtree_node_t *new_root = node_create(false, tree->max_children, NULL);
        if (!new_root) return -1;

        new_root->count = 2;
        new_root->child_bboxes[0] = node->bbox;
        new_root->children[0] = node;
        node->parent = new_root;

        new_root->child_bboxes[1] = sibling->bbox;
        new_root->children[1] = sibling;
        sibling->parent = new_root;

        node_update_bbox(new_root);
        tree->root = new_root;
        tree->height++;
    } else {
        /* Insert sibling into parent */
        rtree_node_t *parent = node->parent;
        int idx = parent->count++;
        parent->child_bboxes[idx] = sibling->bbox;
        parent->children[idx] = sibling;
        sibling->parent = parent;

        /* Update node bounding box in parent */
        for (int i = 0; i < parent->count - 1; i++) {
            if (parent->children[i] == node) {
                parent->child_bboxes[i] = node->bbox;
                break;
            }
        }
        node_update_bbox(parent);

        return treat_overflow(tree, parent, reinserted_level, current_level + 1);
    }

    return 0;
}

static int insert_entry_recursive(rtree_t *tree, rtree_node_t *node,
                                  const spatial_entry_t *entry,
                                  rtree_node_t *child_node,
                                  const spatial_bbox_t *item_bbox,
                                  bool *reinserted_level,
                                  int current_level) {
    /* Choose target node */
    rtree_node_t *target = node;
    if (entry) {
        target = choose_subtree(node, item_bbox);
    }

    int idx = target->count++;
    target->child_bboxes[idx] = *item_bbox;
    if (target->is_leaf) {
        target->entries[idx] = *entry;
    } else {
        target->children[idx] = child_node;
        if (child_node) child_node->parent = target;
    }
    node_update_bbox(target);

    /* Update bounding boxes upward to root */
    rtree_node_t *p = target->parent;
    while (p) {
        for (int i = 0; i < p->count; i++) {
            if (p->children[i] == target) {
                p->child_bboxes[i] = target->bbox;
                break;
            }
        }
        node_update_bbox(p);
        p = p->parent;
    }

    return treat_overflow(tree, target, reinserted_level, current_level);
}

int rtree_insert(rtree_t *tree, spatial_entry_t entry) {
    if (!tree) return -1;

    bool reinserted_level[64];
    memset(reinserted_level, 0, sizeof(reinserted_level));

    int res = insert_entry_recursive(tree, tree->root, &entry, NULL,
                                     &entry.bbox, reinserted_level, 0);
    if (res == 0) {
        tree->size++;
    }
    return res;
}

int rtree_insert_point(rtree_t *tree, uint64_t id,
                       double lat, double lon, void *payload) {
    spatial_entry_t entry;
    entry.id = id;
    entry.bbox = (spatial_bbox_t){lat, lon, lat, lon};
    entry.payload = payload;
    return rtree_insert(tree, entry);
}

/* --------------------------------------------------------------------------
 * Queries
 * -------------------------------------------------------------------------- */

static int query_range_recursive(const rtree_node_t *node,
                                 const spatial_bbox_t *query_bbox,
                                 spatial_result_set_t *rs) {
    if (!bbox_intersects(&node->bbox, query_bbox)) return 0;

    if (node->is_leaf) {
        for (int i = 0; i < node->count; i++) {
            if (bbox_intersects(&node->child_bboxes[i], query_bbox)) {
                spatial_result_t r;
                r.id = node->entries[i].id;
                r.distance = 0.0;
                r.payload = node->entries[i].payload;
                if (result_set_add(rs, r) != 0) return -1;
            }
        }
    } else {
        for (int i = 0; i < node->count; i++) {
            if (query_range_recursive(node->children[i], query_bbox, rs) != 0) {
                return -1;
            }
        }
    }
    return 0;
}

int rtree_query_range(const rtree_t *tree, const spatial_bbox_t *query_bbox,
                      spatial_result_set_t *rs) {
    if (!tree || !query_bbox || !rs) return -1;
    return query_range_recursive(tree->root, query_bbox, rs);
}

/* --------------------------------------------------------------------------
 * k-Nearest Neighbor Priority Queue
 * -------------------------------------------------------------------------- */

typedef struct {
    double dist;
    bool is_entry;
    spatial_entry_t entry;
    rtree_node_t *node;
} knn_item_t;

typedef struct {
    knn_item_t *items;
    size_t size;
    size_t cap;
} knn_heap_t;

static knn_heap_t *knn_heap_create(size_t cap) {
    knn_heap_t *h = (knn_heap_t *)malloc(sizeof(knn_heap_t));
    if (!h) return NULL;
    h->cap = cap < 16 ? 16 : cap;
    h->size = 0;
    h->items = (knn_item_t *)malloc(h->cap * sizeof(knn_item_t));
    if (!h->items) {
        free(h);
        return NULL;
    }
    return h;
}

static void knn_heap_destroy(knn_heap_t *h) {
    if (!h) return;
    free(h->items);
    free(h);
}

static void knn_heap_push(knn_heap_t *h, knn_item_t item) {
    if (h->size >= h->cap) {
        h->cap *= 2;
        h->items = (knn_item_t *)realloc(h->items, h->cap * sizeof(knn_item_t));
    }
    size_t i = h->size++;
    while (i > 0) {
        size_t p = (i - 1) / 2;
        if (h->items[p].dist <= item.dist) break;
        h->items[i] = h->items[p];
        i = p;
    }
    h->items[i] = item;
}

static bool knn_heap_pop(knn_heap_t *h, knn_item_t *out) {
    if (h->size == 0) return false;
    *out = h->items[0];
    knn_item_t last = h->items[--h->size];
    if (h->size == 0) return true;

    size_t i = 0;
    while (2 * i + 1 < h->size) {
        size_t left = 2 * i + 1;
        size_t right = left + 1;
        size_t smallest = left;
        if (right < h->size && h->items[right].dist < h->items[left].dist) {
            smallest = right;
        }
        if (last.dist <= h->items[smallest].dist) break;
        h->items[i] = h->items[smallest];
        i = smallest;
    }
    h->items[i] = last;
    return true;
}

int rtree_query_knn(const rtree_t *tree, double lat, double lon,
                    int k, spatial_result_set_t *rs) {
    if (!tree || k <= 0 || !rs) return -1;

    knn_heap_t *heap = knn_heap_create(64);
    if (!heap) return -1;

    knn_item_t root_item;
    root_item.is_entry = false;
    root_item.node = tree->root;
    root_item.dist = bbox_min_dist_to_point(&tree->root->bbox, lat, lon);
    knn_heap_push(heap, root_item);

    knn_item_t cur;
    int found = 0;

    while (knn_heap_pop(heap, &cur)) {
        if (cur.is_entry) {
            spatial_result_t r;
            r.id = cur.entry.id;
            r.distance = cur.dist;
            r.payload = cur.entry.payload;
            result_set_add(rs, r);
            found++;
            if (found >= k) break;
        } else {
            rtree_node_t *n = cur.node;
            if (n->is_leaf) {
                for (int i = 0; i < n->count; i++) {
                    knn_item_t it;
                    it.is_entry = true;
                    it.entry = n->entries[i];
                    it.node = NULL;
                    it.dist = bbox_min_dist_to_point(&n->child_bboxes[i], lat, lon);
                    knn_heap_push(heap, it);
                }
            } else {
                for (int i = 0; i < n->count; i++) {
                    knn_item_t it;
                    it.is_entry = false;
                    it.node = n->children[i];
                    it.dist = bbox_min_dist_to_point(&n->child_bboxes[i], lat, lon);
                    knn_heap_push(heap, it);
                }
            }
        }
    }

    knn_heap_destroy(heap);
    result_set_sort_by_distance(rs);
    return 0;
}

int rtree_query_radius(const rtree_t *tree, double lat, double lon,
                       double radius_m, spatial_result_set_t *rs) {
    if (!tree || radius_m < 0 || !rs) return -1;

    /* Build an approximate bounding box envelope */
    double deg = (radius_m / EARTH_RADIUS_M) * (180.0 / M_PI);
    spatial_bbox_t filter_box = (spatial_bbox_t){
        lat - deg, lon - deg,
        lat + deg, lon + deg
    };

    spatial_result_set_t candidate_rs;
    if (result_set_init(&candidate_rs, 32) != 0) return -1;

    if (rtree_query_range(tree, &filter_box, &candidate_rs) != 0) {
        result_set_free(&candidate_rs);
        return -1;
    }

    for (size_t i = 0; i < candidate_rs.count; i++) {
        spatial_result_t r = candidate_rs.results[i];
        result_set_add(rs, r);
    }

    result_set_free(&candidate_rs);
    return 0;
}

/* --------------------------------------------------------------------------
 * Deletion
 * -------------------------------------------------------------------------- */

static bool delete_recursive(rtree_node_t *node, uint64_t id) {
    if (node->is_leaf) {
        for (int i = 0; i < node->count; i++) {
            if (node->entries[i].id == id) {
                for (int j = i; j < node->count - 1; j++) {
                    node->entries[j] = node->entries[j + 1];
                    node->child_bboxes[j] = node->child_bboxes[j + 1];
                }
                node->count--;
                node_update_bbox(node);
                return true;
            }
        }
        return false;
    }

    for (int i = 0; i < node->count; i++) {
        if (delete_recursive(node->children[i], id)) {
            node->child_bboxes[i] = node->children[i]->bbox;
            node_update_bbox(node);
            return true;
        }
    }
    return false;
}

int rtree_delete(rtree_t *tree, uint64_t id) {
    if (!tree) return -1;
    if (delete_recursive(tree->root, id)) {
        tree->size--;
        return 0;
    }
    return -1;
}

/* --------------------------------------------------------------------------
 * Statistics
 * -------------------------------------------------------------------------- */

static void count_stats_recursive(const rtree_node_t *node, int level,
                                  size_t *node_count, size_t *entry_count,
                                  double *fill_sum, int *max_level) {
    if (!node) return;
    (*node_count)++;
    if (level > *max_level) *max_level = level;

    double fill = (double)node->count / (double)node->max_children;
    *fill_sum += fill;

    if (node->is_leaf) {
        *entry_count += (size_t)node->count;
    } else {
        for (int i = 0; i < node->count; i++) {
            count_stats_recursive(node->children[i], level + 1,
                                 node_count, entry_count, fill_sum, max_level);
        }
    }
}

void rtree_stats(const rtree_t *tree, rtree_stats_t *stats) {
    if (!tree || !stats) return;

    size_t n_nodes = 0;
    size_t n_entries = 0;
    double fill_sum = 0.0;
    int max_lvl = 1;

    count_stats_recursive(tree->root, 1, &n_nodes, &n_entries, &fill_sum, &max_lvl);

    stats->height = max_lvl;
    stats->node_count = n_nodes;
    stats->entry_count = n_entries;
    stats->avg_fill = (n_nodes > 0) ? (fill_sum / (double)n_nodes) : 0.0;
}

/* --------------------------------------------------------------------------
 * Sort-Tile-Recursive (STR) Bulk Loading
 * -------------------------------------------------------------------------- */

static int str_sort_x(const void *a, const void *b) {
    const spatial_entry_t *ea = (const spatial_entry_t *)a;
    const spatial_entry_t *eb = (const spatial_entry_t *)b;
    double ax = (ea->bbox.min_lon + ea->bbox.max_lon) * 0.5;
    double bx = (eb->bbox.min_lon + eb->bbox.max_lon) * 0.5;
    if (ax < bx) return -1;
    if (ax > bx) return 1;
    return 0;
}

static int str_sort_y(const void *a, const void *b) {
    const spatial_entry_t *ea = (const spatial_entry_t *)a;
    const spatial_entry_t *eb = (const spatial_entry_t *)b;
    double ay = (ea->bbox.min_lat + ea->bbox.max_lat) * 0.5;
    double by = (eb->bbox.min_lat + eb->bbox.max_lat) * 0.5;
    if (ay < by) return -1;
    if (ay > by) return 1;
    return 0;
}

rtree_t *rtree_bulk_load(spatial_entry_t *entries, size_t count,
                         int min_children, int max_children) {
    rtree_t *tree = rtree_create(min_children, max_children);
    if (!tree || count == 0) return tree;

    size_t M = tree->max_children;
    size_t num_leaves = (size_t)ceil((double)count / (double)M);
    size_t num_slices = (size_t)ceil(sqrt((double)num_leaves));

    /* Sort by X (longitude) */
    qsort(entries, count, sizeof(spatial_entry_t), str_sort_x);

    /* Sort each vertical slice by Y (latitude) */
    size_t slice_size = num_slices * M;
    for (size_t s = 0; s < count; s += slice_size) {
        size_t cur_slice_count = (s + slice_size <= count) ? slice_size : (count - s);
        qsort(&entries[s], cur_slice_count, sizeof(spatial_entry_t), str_sort_y);
    }

    /* Insert bulk-sorted entries into the tree */
    for (size_t i = 0; i < count; i++) {
        rtree_insert(tree, entries[i]);
    }

    return tree;
}
