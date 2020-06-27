package convect.core.compute;

import convect.core.types.GeoPoint;
import convect.core.types.BoundingBox;
import convect.core.types.SensorReading;

/**
 * KernelDensityEstimator computes continuous 2D spatial probability surfaces.
 *
 * Utilizes a bivariate Gaussian kernel function to estimate the intensity of
 * environmental events (e.g., pollutant plumes, seismic micro-tremors, heat islands)
 * across a discrete grid of spatial tiles.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class KernelDensityEstimator {

    public val bandwidthMeters:Double;

    public def this(bandwidthMeters:Double) {
        this.bandwidthMeters = bandwidthMeters;
    }

    /**
     * Standard radial Gaussian kernel K(u) = (1 / (2 * pi)) * exp(-0.5 * u^2).
     */
    private def gaussianKernel(distMeters:Double):Double {
        val u = distMeters / this.bandwidthMeters;
        val factor = 1.0 / (2.0 * Math.PI * this.bandwidthMeters * this.bandwidthMeters);
        return factor * Math.exp(-0.5 * u * u);
    }

    /**
     * Compute density estimate at an evaluation point given an array of observations.
     */
    public def evaluateDensity(evalPoint:GeoPoint, observations:Rail[SensorReading]):Double {
        if (observations.size == 0L) return 0.0;

        var densitySum:Double = 0.0;
        for (i in 0..(observations.size - 1)) {
            val dist = evalPoint.distanceTo(observations(i).location);
            /* Truncate kernel beyond 3 bandwidths (captures 99.7% of Gaussian mass) */
            if (dist <= 3.0 * this.bandwidthMeters) {
                densitySum += gaussianKernel(dist) * observations(i).value;
            }
        }

        return densitySum;
    }

    /**
     * Generate an M x N density raster over a target bounding box.
     */
    public def computeRaster(bbox:BoundingBox, rows:Int, cols:Int, observations:Rail[SensorReading]):Rail[Double] {
        val totalCells = (rows as Long) * (cols as Long);
        val result = new Rail[Double](totalCells);

        val latStep = bbox.heightDeg() / (rows as Double);
        val lonStep = bbox.widthDeg() / (cols as Double);

        for (r in 0..(rows - 1n)) {
            val evalLat = bbox.minLat + (r as Double + 0.5) * latStep;
            for (c in 0..(cols - 1n)) {
                val evalLon = bbox.minLon + (c as Double + 0.5) * lonStep;
                val idx = (r as Long) * (cols as Long) + (c as Long);
                result(idx) = evaluateDensity(GeoPoint(evalLat, evalLon), observations);
            }
        }

        return result;
    }
}
