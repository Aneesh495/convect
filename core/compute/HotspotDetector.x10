package convect.core.compute;

import convect.core.types.GeoPoint;
import convect.core.types.SensorReading;

/**
 * HotspotDetector computes Getis-Ord Gi* spatial clustering statistics.
 *
 * Given a set of spatial observations, Gi* identifies whether high values (hotspots)
 * or low values (coldspots) cluster spatially more than expected by chance.
 * Returns a standard normal Z-score for each feature:
 *   Z > +1.96 indicates a statistically significant hot spot (p < 0.05)
 *   Z < -1.96 indicates a statistically significant cold spot (p < 0.05)
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class HotspotDetector {

    public val neighborhoodRadiusMeters:Double;

    public def this(neighborhoodRadiusMeters:Double) {
        this.neighborhoodRadiusMeters = neighborhoodRadiusMeters;
    }

    /**
     * Compute Getis-Ord Gi* Z-scores for each observation in the array.
     */
    public def computeZScores(readings:Rail[SensorReading]):Rail[Double] {
        val n = readings.size;
        val zScores = new Rail[Double](n);
        if (n < 3L) return zScores;

        /* Calculate global mean and standard deviation */
        var sumVal:Double = 0.0;
        var sumSqVal:Double = 0.0;
        for (i in 0..(n - 1L)) {
            val v = readings(i).value;
            sumVal += v;
            sumSqVal += v * v;
        }

        val nDouble = n as Double;
        val globalMean = sumVal / nDouble;
        val globalVariance = (sumSqVal / nDouble) - (globalMean * globalMean);
        val globalStddev = Math.sqrt(Math.max(1e-9, globalVariance));

        /* Compute Gi* for each location i */
        for (i in 0..(n - 1L)) {
            var sumWeights:Double = 0.0;
            var sumWeightSq:Double = 0.0;
            var localWeightedSum:Double = 0.0;

            val loc_i = readings(i).location;

            for (j in 0..(n - 1L)) {
                val dist = loc_i.distanceTo(readings(j).location);
                /* Binary spatial weights matrix W_ij based on neighborhood radius */
                if (dist <= this.neighborhoodRadiusMeters) {
                    val w:Double = 1.0;
                    sumWeights += w;
                    sumWeightSq += w * w;
                    localWeightedSum += w * readings(j).value;
                }
            }

            /* Getis-Ord numerator: sum(w_ij * x_j) - X_bar * sum(w_ij) */
            val numerator = localWeightedSum - (globalMean * sumWeights);

            /* Getis-Ord denominator standard error: S * sqrt((n * sum(w^2) - (sum w)^2) / (n - 1)) */
            val term1 = (nDouble * sumWeightSq) - (sumWeights * sumWeights);
            val denomInner = Math.max(0.0, term1 / (nDouble - 1.0));
            val denominator = globalStddev * Math.sqrt(denomInner);

            if (denominator > 1e-9) {
                zScores(i) = numerator / denominator;
            } else {
                zScores(i) = 0.0;
            }
        }

        return zScores;
    }
}
