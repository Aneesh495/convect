package convect.core.compute;

import convect.core.types.GeoPoint;
import convect.core.types.SensorReading;
import x10.util.ArrayList;

/**
 * SpatialInterpolator reconstructs continuous environmental fields from discrete sensor readings.
 *
 * Implements Inverse Distance Weighting (Shepard's Method) with configurable power parameter p.
 * For unmonitored coordinates, computes a weighted average of nearby reporting stations where
 * weights decay inversely with great-circle distance: w_i = (1 / d_i)^p.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class SpatialInterpolator {

    public val power:Double;
    public val maxDistanceMeters:Double;
    public val minObservations:Int;

    public def this(power:Double, maxDistanceMeters:Double, minObservations:Int) {
        this.power = power;
        this.maxDistanceMeters = maxDistanceMeters;
        this.minObservations = minObservations;
    }

    public def this() {
        this.power = 2.0; /* Standard Inverse Distance Squared */
        this.maxDistanceMeters = 50000.0; /* 50 km default cutoff */
        this.minObservations = 3n;
    }

    /**
     * Interpolates the estimated value at target location from neighboring readings.
     * Returns NaN if fewer than minObservations fall within maxDistanceMeters.
     */
    public def interpolate(target:GeoPoint, neighbors:Rail[SensorReading]):Double {
        var weightSum:Double = 0.0;
        var valueSum:Double = 0.0;
        var validCount:Int = 0n;

        for (i in 0..(neighbors.size - 1)) {
            val r = neighbors(i);
            val dist = target.distanceTo(r.location);

            /* Exact match on top of a sensor station */
            if (dist < 1.0) {
                return r.value;
            }

            if (dist <= this.maxDistanceMeters) {
                val w = 1.0 / Math.pow(dist, this.power);
                weightSum += w;
                valueSum += w * r.value;
                validCount++;
            }
        }

        if (validCount < this.minObservations || weightSum <= 0.0) {
            return Double.NaN;
        }

        return valueSum / weightSum;
    }
}
