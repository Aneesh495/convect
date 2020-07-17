package convect.core.detect;

import convect.core.types.GeoPoint;
import convect.core.types.SensorReading;
import x10.util.ArrayList;

/**
 * LocalOutlierFactor (LOF) detects spatial sensor readings that significantly
 * deviate from their local geographic neighborhood.
 *
 * Implements the Breunig et al. (2000) density-based anomaly algorithm:
 *   1. For each sensor reading p, discovers its k-nearest spatial neighbors N_k(p).
 *   2. Evaluates reachability distance: reach_dist_k(p, o) = max(k_dist(o), dist(p, o)).
 *   3. Evaluates local reachability density: lrd_k(p) = |N_k(p)| / sum(reach_dist_k(p, o)).
 *   4. Computes LOF score: LOF_k(p) = avg(lrd_k(o)) / lrd_k(p).
 *
 * LOF ~ 1 indicates typical spatial continuity.
 * LOF > 1.5 indicates an isolated sensor reading inconsistent with nearby stations.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class LocalOutlierFactor {

    public val k:Int;
    public val thresholdLOF:Double;

    public def this(k:Int, thresholdLOF:Double) {
        this.k = (if (k < 2n) 2n else k);
        this.thresholdLOF = thresholdLOF;
    }

    public def this() {
        this.k = 5n;
        this.thresholdLOF = 1.6;
    }

    /**
     * Compute spatial Euclidean distance between reading coordinates and values.
     */
    private def featureDist(a:SensorReading, b:SensorReading):Double {
        val geoDist = a.distanceTo(b);
        /* Scale value difference to comparable metric space (1 deg C ~ 5 km) */
        val valDiff = Math.abs(a.value - b.value) * 5000.0;
        return Math.sqrt(geoDist * geoDist + valDiff * valDiff);
    }

    /**
     * Detect spatial anomalies across an array of sensor observations.
     */
    public def detect(readings:Rail[SensorReading]):ArrayList[AnomalyResult] {
        val results = new ArrayList[AnomalyResult]();
        val n = readings.size;
        if (n <= (this.k as Long)) return results;

        /* Precompute pairwise feature distances */
        val dists = new Rail[Double](n * n);
        for (i in 0..(n - 1L)) {
            for (j in 0..(n - 1L)) {
                if (i == j) {
                    dists(i * n + j) = 0.0;
                } else {
                    dists(i * n + j) = featureDist(readings(i), readings(j));
                }
            }
        }

        /* Calculate k-distance for each point */
        val kDist = new Rail[Double](n);
        for (i in 0..(n - 1L)) {
            /* Find k-th smallest distance from i */
            val row = new Rail[Double](n, (j:Long) => dists(i * n + j));
            /* Simple selection sort for k smallest elements */
            for (m in 0..(this.k as Long)) {
                var minIdx = m;
                for (cur in (m + 1L)..(n - 1L)) {
                    if (row(cur) < row(minIdx)) minIdx = cur;
                }
                val tmp = row(m);
                row(m) = row(minIdx);
                row(minIdx) = tmp;
            }
            kDist(i) = row(this.k as Long);
        }

        /* Calculate local reachability density (lrd) for each point */
        val lrd = new Rail[Double](n);
        for (i in 0..(n - 1L)) {
            var sumReachDist:Double = 0.0;
            var neighborCount:Long = 0L;

            for (j in 0..(n - 1L)) {
                if (i != j && dists(i * n + j) <= kDist(i)) {
                    val reachDist = Math.max(kDist(j), dists(i * n + j));
                    sumReachDist += reachDist;
                    neighborCount++;
                }
            }

            if (neighborCount > 0L && sumReachDist > 1e-6) {
                lrd(i) = (neighborCount as Double) / sumReachDist;
            } else {
                lrd(i) = 1e-6;
            }
        }

        /* Calculate LOF score for each point */
        for (i in 0..(n - 1L)) {
            var sumLrdRatios:Double = 0.0;
            var neighborCount:Long = 0L;
            var expectedVal:Double = 0.0;

            for (j in 0..(n - 1L)) {
                if (i != j && dists(i * n + j) <= kDist(i)) {
                    sumLrdRatios += (lrd(j) / lrd(i));
                    expectedVal += readings(j).value;
                    neighborCount++;
                }
            }

            if (neighborCount > 0L) {
                val lofScore = sumLrdRatios / (neighborCount as Double);
                val avgNeighborVal = expectedVal / (neighborCount as Double);

                if (lofScore >= this.thresholdLOF) {
                    val confidence = Math.min(0.99, (lofScore - 1.0) / (this.thresholdLOF));
                    val anom = AnomalyResult(
                        1n, /* SPATIAL_OUTLIER */
                        readings(i).sensorId,
                        readings(i).location,
                        readings(i).timestamp,
                        readings(i).value,
                        avgNeighborVal,
                        lofScore,
                        confidence
                    );
                    results.add(anom);
                }
            }
        }

        return results;
    }
}
