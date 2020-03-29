/*
 * convect_spatial_bridge.h - JNI native bridge header for Convect spatial index.
 *
 * Exposes high-performance C spatial algorithms to Managed X10 and JVM runtimes
 * through standardized JNI method signatures.
 *
 * Target Java class: convect.core.index.NativeSpatialIndex
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef CONVECT_SPATIAL_BRIDGE_H
#define CONVECT_SPATIAL_BRIDGE_H

#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

/* R-tree native wrappers */
JNIEXPORT jlong JNICALL Java_convect_core_index_NativeSpatialIndex_nativeCreateRtree
  (JNIEnv *env, jclass cls, jint min_children, jint max_children);

JNIEXPORT void JNICALL Java_convect_core_index_NativeSpatialIndex_nativeDestroyRtree
  (JNIEnv *env, jclass cls, jlong handle);

JNIEXPORT jint JNICALL Java_convect_core_index_NativeSpatialIndex_nativeRtreeInsert
  (JNIEnv *env, jclass cls, jlong handle, jlong id, jdouble min_lat, jdouble min_lon, jdouble max_lat, jdouble max_lon);

JNIEXPORT jlongArray JNICALL Java_convect_core_index_NativeSpatialIndex_nativeRtreeQueryRange
  (JNIEnv *env, jclass cls, jlong handle, jdouble min_lat, jdouble min_lon, jdouble max_lat, jdouble max_lon);

JNIEXPORT jlongArray JNICALL Java_convect_core_index_NativeSpatialIndex_nativeRtreeQueryKnn
  (JNIEnv *env, jclass cls, jlong handle, jdouble lat, jdouble lon, jint k);

JNIEXPORT jint JNICALL Java_convect_core_index_NativeSpatialIndex_nativeRtreeDelete
  (JNIEnv *env, jclass cls, jlong handle, jlong id);

/* Geohash native wrappers */
JNIEXPORT jstring JNICALL Java_convect_core_index_NativeSpatialIndex_nativeGeohashEncode
  (JNIEnv *env, jclass cls, jdouble lat, jdouble lon, jint precision);

JNIEXPORT jdoubleArray JNICALL Java_convect_core_index_NativeSpatialIndex_nativeGeohashDecode
  (JNIEnv *env, jclass cls, jstring hash);

/* Hilbert curve native wrappers */
JNIEXPORT jlong JNICALL Java_convect_core_index_NativeSpatialIndex_nativeHilbertEncode
  (JNIEnv *env, jclass cls, jdouble lat, jdouble lon, jint order);

JNIEXPORT jdoubleArray JNICALL Java_convect_core_index_NativeSpatialIndex_nativeHilbertDecode
  (JNIEnv *env, jclass cls, jlong d, jint order);

/* Geodesic distance native wrapper */
JNIEXPORT jdouble JNICALL Java_convect_core_index_NativeSpatialIndex_nativeHaversine
  (JNIEnv *env, jclass cls, jdouble lat1, jdouble lon1, jdouble lat2, jdouble lon2);

#ifdef __cplusplus
}
#endif

#endif /* CONVECT_SPATIAL_BRIDGE_H */
