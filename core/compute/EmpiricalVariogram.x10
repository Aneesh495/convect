/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.compute.EmpiricalVariogram
 *
 * Computes empirical spatial semivariograms and theoretical covariance models
 * (Spherical, Exponential, Gaussian) for optimal spatial prediction in X10.
 */

package convect.core.compute;

import convect.core.types.GeoPoint;
import convect.core.types.SensorReading;
import convect.core.math.VectorMath;

public class EmpiricalVariogram {

    public static val MODEL_SPHERICAL: Long = 0;
    public static val MODEL_EXPONENTIAL: Long = 1;
    public static val MODEL_GAUSSIAN: Long = 2;

    public val modelType: Long;
    public val nugget: Double;
    public val sill: Double;
    public val range: Double; // meters

    public def this(modelType: Long, nugget: Double, sill: Double, range: Double) {
        this.modelType = modelType;
        this.nugget = nugget;
        this.sill = sill;
        this.range = range;
    }

    /**
     * Theoretical semivariance gamma(h) for spatial lag distance h (in meters).
     */
    public def semivariance(h: Double): Double {
        if (h <= 0.0) {
            return 0.0;
        }
        val c0 = this.nugget;
        val c = this.sill - this.nugget;
        val a = this.range;

        if (modelType == MODEL_SPHERICAL) {
            if (h >= a) {
                return this.sill;
            }
            val ratio = h / a;
            return c0 + c * (1.5 * ratio - 0.5 * ratio * ratio * ratio);
        } else if (modelType == MODEL_EXPONENTIAL) {
            return c0 + c * (1.0 - Math.exp(-3.0 * h / a));
        } else {
            // MODEL_GAUSSIAN
            val ratio = h / a;
            return c0 + c * (1.0 - Math.exp(-3.0 * ratio * ratio));
        }
    }

    /**
     * Covariance C(h) = Sill - gamma(h).
     */
    public def covariance(h: Double): Double {
        if (h <= 0.0) {
            return this.sill;
        }
        return Math.max(0.0, this.sill - semivariance(h));
    }

    /**
     * Estimate empirical variogram points from a collection of sensor readings.
     * Divides distance lags into numBins intervals up to maxDistance.
     */
    public static def estimate(readings: Rail[SensorReading], numBins: Long, maxDistance: Double): Rail[Rail[Double]] {
        val n = readings.size;
        val binSize = maxDistance / (numBins as Double);
        val sumGamma = new Rail[Double](numBins);
        val count = new Rail[Long](numBins);

        for (i in 0..(n - 1)) {
            val pi = readings(i).point;
            val zi = readings(i).value;
            for (j in (i + 1)..(n - 1)) {
                val pj = readings(j).point;
                val zj = readings(j).value;

                val dist = pi.haversineDistance(pj);
                if (dist <= maxDistance) {
                    var bin = (dist / binSize) as Long;
                    if (bin >= numBins) {
                        bin = numBins - 1;
                    }
                    val diff = zi - zj;
                    sumGamma(bin) += 0.5 * diff * diff;
                    count(bin) += 1;
                }
            }
        }

        // Return rows of [lagCenter, gamma, pairCount]
        val result = new Rail[Rail[Double]](numBins);
        for (b in 0..(numBins - 1)) {
            val row = new Rail[Double](3);
            row(0) = (b as Double + 0.5) * binSize;
            if (count(b) > 0) {
                row(1) = sumGamma(b) / (count(b) as Double);
            } else {
                row(1) = 0.0;
            }
            row(2) = count(b) as Double;
            result(b) = row;
        }
        return result;
    }
}
