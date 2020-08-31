/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.compute.SpatiotemporalKriging
 *
 * Distributed Ordinary Kriging spatial interpolator using Cholesky
 * decomposition of theoretical covariance matrices in X10.
 */

package convect.core.compute;

import convect.core.types.GeoPoint;
import convect.core.types.SensorReading;
import convect.core.math.MatrixOperations;
import convect.core.math.CholeskyDecomposition;

public class SpatiotemporalKriging {

    private val variogram: EmpiricalVariogram;
    private val maxNeighbors: Long;

    public def this(variogram: EmpiricalVariogram, maxNeighbors: Long) {
        this.variogram = variogram;
        this.maxNeighbors = maxNeighbors;
    }

    public def this(variogram: EmpiricalVariogram) {
        this(variogram, 32);
    }

    /**
     * Kriging prediction result holding point estimate and estimation variance.
     */
    public static class KrigingResult {
        public val estimate: Double;
        public val variance: Double;
        public val numNeighbors: Long;

        public def this(estimate: Double, variance: Double, numNeighbors: Long) {
            this.estimate = estimate;
            this.variance = variance;
            this.numNeighbors = numNeighbors;
        }
    }

    /**
     * Interpolate value at target point using Ordinary Kriging over neighbor readings.
     */
    public def predict(target: GeoPoint, readings: Rail[SensorReading]): KrigingResult {
        val total = readings.size;
        if (total == 0) {
            return new KrigingResult(0.0, Double.MAX_VALUE, 0);
        }
        if (total == 1) {
            return new KrigingResult(readings(0).value, variogram.sill, 1);
        }

        // Limit to closest maxNeighbors to maintain tight O(K^3) solve time
        val k = Math.min(total, this.maxNeighbors);
        val sorted = new Rail[SensorReading](total);
        for (i in 0..(total - 1)) {
            sorted(i) = readings(i);
        }

        // Sort by distance to target point (insertion sort for small K)
        for (i in 1..(total - 1)) {
            val key = sorted(i);
            val dKey = target.haversineDistance(key.point);
            var j: Long = i - 1;
            while (j >= 0 && target.haversineDistance(sorted(j).point) > dKey) {
                sorted(j + 1) = sorted(j);
                j--;
            }
            sorted(j + 1) = key;
        }

        // Build Ordinary Kriging system of size (k + 1) x (k + 1)
        // [ C   1 ] [ w ] = [ c0 ]
        // [ 1^T 0 ] [ mu]   [ 1  ]
        val dim = k + 1;
        val A = MatrixOperations.zeros(dim, dim);
        val b = new Rail[Double](dim);

        for (i in 0..(k - 1)) {
            for (j in 0..(k - 1)) {
                val dist = sorted(i).point.haversineDistance(sorted(j).point);
                A(i)(j) = variogram.covariance(dist);
            }
            A(i)(k) = 1.0;
            A(k)(i) = 1.0;

            val dist0 = target.haversineDistance(sorted(i).point);
            b(i) = variogram.covariance(dist0);
        }
        A(k)(k) = 0.0;
        b(k) = 1.0;

        // Solve Ordinary Kriging system with pseudo-inverse / regularized solver
        // For augmented (k+1) system with zero bottom-right entry, apply diagonal regularization:
        val jitter = 1.0e-5;
        A(k)(k) = -jitter;
        val chol = new CholeskyDecomposition(A, jitter);
        val weights = chol.solve(b);

        var prediction: Double = 0.0;
        var estVariance: Double = variogram.sill;

        for (i in 0..(k - 1)) {
            prediction += weights(i) * sorted(i).value;
            estVariance -= weights(i) * b(i);
        }
        estVariance -= weights(k); // Subtract Lagrange multiplier mu

        if (estVariance < 0.0) {
            estVariance = 0.0;
        }

        return new KrigingResult(prediction, estVariance, k);
    }
}
