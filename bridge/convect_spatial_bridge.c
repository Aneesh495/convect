/*
 * convect_spatial_bridge.c - Implementation of JNI bridge for Convect spatial index.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#include "convect_spatial_bridge.h"
#include "../index/spatial_types.h"
#include "../index/rtree/rtree.h"
#include "../index/geohash/geohash.h"
#include "../index/hilbert/hilbert.h"

#include <stdlib.h>
#include <string.h>

JNIEXPORT jlong JNICALL Java_convect_core_index_NativeSpatialIndex_nativeCreateRtree
  (JNIEnv *env, jclass cls, jint min_children, jint max_children) {
    (void)env; (void)cls;
    rtree_t *tree = rtree_create(min_children, max_children);
    return (jlong)(uintptr_t)tree;
}

JNIEXPORT void JNICALL Java_convect_core_index_NativeSpatialIndex_nativeDestroyRtree
  (JNIEnv *env, jclass cls, jlong handle) {
    (void)env; (void)cls;
    rtree_t *tree = (rtree_t *)(uintptr_t)handle;
    if (tree) {
        rtree_destroy(tree);
    }
}

JNIEXPORT jint JNICALL Java_convect_core_index_NativeSpatialIndex_nativeRtreeInsert
  (JNIEnv *env, jclass cls, jlong handle, jlong id, jdouble min_lat, jdouble min_lon, jdouble max_lat, jdouble max_lon) {
    (void)env; (void)cls;
    rtree_t *tree = (rtree_t *)(uintptr_t)handle;
    if (!tree) return -1;

    spatial_entry_t entry;
    entry.id = (uint64_t)id;
    entry.bbox = (spatial_bbox_t){min_lat, min_lon, max_lat, max_lon};
    entry.payload = NULL;

    return rtree_insert(tree, entry);
}

JNIEXPORT jlongArray JNICALL Java_convect_core_index_NativeSpatialIndex_nativeRtreeQueryRange
  (JNIEnv *env, jclass cls, jlong handle, jdouble min_lat, jdouble min_lon, jdouble max_lat, jdouble max_lon) {
    (void)cls;
    rtree_t *tree = (rtree_t *)(uintptr_t)handle;
    if (!tree) return NULL;

    spatial_bbox_t qb = {min_lat, min_lon, max_lat, max_lon};
    spatial_result_set_t rs;
    if (result_set_init(&rs, 32) != 0) return NULL;

    if (rtree_query_range(tree, &qb, &rs) != 0) {
        result_set_free(&rs);
        return NULL;
    }

    jlongArray arr = (*env)->NewLongArray(env, (jsize)rs.count);
    if (!arr) {
        result_set_free(&rs);
        return NULL;
    }

    if (rs.count > 0) {
        jlong *elems = (jlong *)malloc(rs.count * sizeof(jlong));
        for (size_t i = 0; i < rs.count; i++) {
            elems[i] = (jlong)rs.results[i].id;
        }
        (*env)->SetLongArrayRegion(env, arr, 0, (jsize)rs.count, elems);
        free(elems);
    }

    result_set_free(&rs);
    return arr;
}

JNIEXPORT jlongArray JNICALL Java_convect_core_index_NativeSpatialIndex_nativeRtreeQueryKnn
  (JNIEnv *env, jclass cls, jlong handle, jdouble lat, jdouble lon, jint k) {
    (void)cls;
    rtree_t *tree = (rtree_t *)(uintptr_t)handle;
    if (!tree || k <= 0) return NULL;

    spatial_result_set_t rs;
    if (result_set_init(&rs, (size_t)k) != 0) return NULL;

    if (rtree_query_knn(tree, lat, lon, k, &rs) != 0) {
        result_set_free(&rs);
        return NULL;
    }

    jlongArray arr = (*env)->NewLongArray(env, (jsize)rs.count);
    if (!arr) {
        result_set_free(&rs);
        return NULL;
    }

    if (rs.count > 0) {
        jlong *elems = (jlong *)malloc(rs.count * sizeof(jlong));
        for (size_t i = 0; i < rs.count; i++) {
            elems[i] = (jlong)rs.results[i].id;
        }
        (*env)->SetLongArrayRegion(env, arr, 0, (jsize)rs.count, elems);
        free(elems);
    }

    result_set_free(&rs);
    return arr;
}

JNIEXPORT jint JNICALL Java_convect_core_index_NativeSpatialIndex_nativeRtreeDelete
  (JNIEnv *env, jclass cls, jlong handle, jlong id) {
    (void)env; (void)cls;
    rtree_t *tree = (rtree_t *)(uintptr_t)handle;
    if (!tree) return -1;
    return rtree_delete(tree, (uint64_t)id);
}

JNIEXPORT jstring JNICALL Java_convect_core_index_NativeSpatialIndex_nativeGeohashEncode
  (JNIEnv *env, jclass cls, jdouble lat, jdouble lon, jint precision) {
    (void)cls;
    if (precision <= 0 || precision > GEOHASH_MAX_PRECISION) return NULL;
    char buf[GEOHASH_MAX_PRECISION + 1];
    if (geohash_encode(lat, lon, (size_t)precision, buf) != 0) return NULL;
    return (*env)->NewStringUTF(env, buf);
}

JNIEXPORT jdoubleArray JNICALL Java_convect_core_index_NativeSpatialIndex_nativeGeohashDecode
  (JNIEnv *env, jclass cls, jstring hash) {
    (void)cls;
    if (!hash) return NULL;
    const char *str = (*env)->GetStringUTFChars(env, hash, NULL);
    if (!str) return NULL;

    double lat, lon;
    spatial_bbox_t bbox;
    int rc = geohash_decode(str, &lat, &lon, &bbox);
    (*env)->ReleaseStringUTFChars(env, hash, str);

    if (rc != 0) return NULL;

    jdoubleArray arr = (*env)->NewDoubleArray(env, 6);
    if (!arr) return NULL;

    jdouble data[6] = {lat, lon, bbox.min_lat, bbox.min_lon, bbox.max_lat, bbox.max_lon};
    (*env)->SetDoubleArrayRegion(env, arr, 0, 6, data);
    return arr;
}

JNIEXPORT jlong JNICALL Java_convect_core_index_NativeSpatialIndex_nativeHilbertEncode
  (JNIEnv *env, jclass cls, jdouble lat, jdouble lon, jint order) {
    (void)env; (void)cls;
    if (order <= 0 || order > HILBERT_MAX_ORDER) return 0;
    return (jlong)hilbert_from_latlon(lat, lon, (uint32_t)order);
}

JNIEXPORT jdoubleArray JNICALL Java_convect_core_index_NativeSpatialIndex_nativeHilbertDecode
  (JNIEnv *env, jclass cls, jlong d, jint order) {
    (void)cls;
    if (order <= 0 || order > HILBERT_MAX_ORDER) return NULL;

    double lat, lon;
    hilbert_to_latlon((uint64_t)d, (uint32_t)order, &lat, &lon);

    jdoubleArray arr = (*env)->NewDoubleArray(env, 2);
    if (!arr) return NULL;

    jdouble data[2] = {lat, lon};
    (*env)->SetDoubleArrayRegion(env, arr, 0, 2, data);
    return arr;
}

JNIEXPORT jdouble JNICALL Java_convect_core_index_NativeSpatialIndex_nativeHaversine
  (JNIEnv *env, jclass cls, jdouble lat1, jdouble lon1, jdouble lat2, jdouble lon2) {
    (void)env; (void)cls;
    return point_distance_haversine(lat1, lon1, lat2, lon2);
}
