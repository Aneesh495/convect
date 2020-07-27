package convect.core.detect;

import convect.core.types.GeoPoint;
import convect.core.types.SensorReading;
import x10.util.ArrayList;

/**
 * MoranSpatialAutocorrelation evaluates spatial autocorrelation across sensor clusters.
 *
 * Implements Anselin's Local Indicators of Spatial Association (LISA) to detect
 * localized breakdowns in Tobler's First Law of Geography ("everything is related
 * to everything else, but near things are more related than distant things").
 *
 * Identifies four distinct spatial regimes:
 *   - High-High: Cluster of high values
 *   - Low-Low: Cluster of low values
 *   - High-Low: Spatial outlier (high reading surrounded by low readings)
 *   - Low-High: Spatial outlier (low reading surrounded by high readings)
 *
 * Emits AnomalyResult for statistically significant High-Low and Low-High outliers.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class MoranSpatialAutocorrelation {

    public val neighborhoodRadiusMeters:Double;
    public val significanceThresholdZ:Double;

    public def this(neighborhoodRadiusMeters:Double, significanceThresholdZ:Double) {
        this.neighborhoodRadiusMeters = neighborhoodRadiusMeters;
        this.significanceThresholdZ = significanceThresholdZ;
    }

    public def this() {
        this(30000.0, 2.0); /* 30 km radius, Z >= 2.0 (~p < 0.05) */
    }

    /**
     * Compute Global Moran's I index for a collection of spatial observations.
     * Returns a value in [-1, +1] where +1 = strong clustering, -1 = dispersion, 0 = random.
     */
    public def computeGlobalMoran(readings:Rail[SensorReading]):Double {
        val n = readings.size;
        if (n < 4L) return 0.0;

        var sumVal:Double = 0.0;
        for (i in 0..(n - 1L)) sumVal += readings(i).value;
        val meanVal = sumVal / (n as Double);

        var numSum:Double = 0.0;
        var denomSum:Double = 0.0;
        var s0:Double = 0.0;

        for (i in 0..(n - 1L)) {
            val dev_i = readings(i).value - meanVal;
            denomSum += dev_i * dev_i;

            for (j in 0..(n - 1L)) {
                if (i != j) {
                    val dist = readings(i).distanceTo(readings(j));
                    if (dist <= this.neighborhoodRadiusMeters && dist > 0.0) {
                        /* Distance inverse weight */
                        val w = 1.0 / dist;
                        val dev_j = readings(j).value - meanVal;
                        numSum += w * dev_i * dev_j;
                        s0 += w;
                    }
                }
            }
        }

        if (denomSum <= 1e-9 || s0 <= 1e-9) return 0.0;

        return ((n as Double) / s0) * (numSum / denomSum);
    }

    /**
     * Detect local spatial outliers (High-Low and Low-High) using LISA.
     */
    public def detectOutliers(readings:Rail[SensorReading]):ArrayList[AnomalyResult] {
        val results = new ArrayList[AnomalyResult]();
        val n = readings.size;
        if (n < 5L) return results;

        var sumVal:Double = 0.0;
        for (i in 0..(n - 1L)) sumVal += readings(i).value;
        val meanVal = sumVal / (n as Double);

        var m2:Double = 0.0;
        for (i in 0..(n - 1L)) {
            val dev = readings(i).value - meanVal;
            m2 += dev * dev;
        }
        val variance = m2 / (n as Double);
        if (variance <= 1e-9) return results;

        /* Calculate Local Moran's I_i for each station */
        for (i in 0..(n - 1L)) {
            val dev_i = readings(i).value - meanVal;
            var weightedLag:Double = 0.0;
            var sumWeights:Double = 0.0;

            for (j in 0..(n - 1L)) {
                if (i != j) {
                    val dist = readings(i).distanceTo(readings(j));
                    if (dist <= this.neighborhoodRadiusMeters) {
                        val w = 1.0;
                        weightedLag += w * (readings(j).value - meanVal);
                        sumWeights += w;
                    }
                }
            }

            if (sumWeights > 0.0) {
                /* Local Moran's I_i = (z_i / m2) * sum_j(w_ij * z_j) */
                val localI = (dev_i / variance) * weightedLag;

                /* Negative local I indicates negative spatial autocorrelation (outlier) */
                if (localI < 0.0) {
                    val zScore = Math.abs(localI) / Math.sqrt(variance);
                    if (zScore >= this.significanceThresholdZ) {
                        val expected = meanVal + (weightedLag / sumWeights);
                        val conf = Math.min(0.99, (zScore / this.significanceThresholdZ) * 0.7);

                        val anom = AnomalyResult(
                            3n, /* SPATIAL_AUTOCORRELATION_BREAKDOWN */
                            readings(i).sensorId,
                            readings(i).location,
                            readings(i).timestamp,
                            readings(i).value,
                            expected,
                            zScore,
                            conf
                        );
                        results.add(anom);
                    }
                }
            }
        }

        return results;
    }
}
