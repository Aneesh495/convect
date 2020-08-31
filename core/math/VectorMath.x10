/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.math.VectorMath
 *
 * High-performance vector arithmetic utilities for spatiotemporal interpolation,
 * distance metrics, and multivariate spatial statistics in X10.
 */

package convect.core.math;

public class VectorMath {

    /**
     * Compute dot product of two vectors of equal length.
     */
    public static def dot(a: Rail[Double], b: Rail[Double]): Double {
        val len = Math.min(a.size, b.size);
        var sum: Double = 0.0;
        for (i in 0..(len - 1)) {
            sum += a(i) * b(i);
        }
        return sum;
    }

    /**
     * Compute Euclidean L2 norm of a vector.
     */
    public static def norm2(v: Rail[Double]): Double {
        return Math.sqrt(dot(v, v));
    }

    /**
     * Compute Euclidean distance between two coordinate vectors.
     */
    public static def euclideanDistance(a: Rail[Double], b: Rail[Double]): Double {
        val len = Math.min(a.size, b.size);
        var sumSq: Double = 0.0;
        for (i in 0..(len - 1)) {
            val diff = a(i) - b(i);
            sumSq += diff * diff;
        }
        return Math.sqrt(sumSq);
    }

    /**
     * Compute Manhattan L1 distance between two coordinate vectors.
     */
    public static def manhattanDistance(a: Rail[Double], b: Rail[Double]): Double {
        val len = Math.min(a.size, b.size);
        var sum: Double = 0.0;
        for (i in 0..(len - 1)) {
            sum += Math.abs(a(i) - b(i));
        }
        return sum;
    }

    /**
     * Element-wise vector addition: r = a + b.
     */
    public static def add(a: Rail[Double], b: Rail[Double]): Rail[Double] {
        val len = Math.min(a.size, b.size);
        val result = new Rail[Double](len);
        for (i in 0..(len - 1)) {
            result(i) = a(i) + b(i);
        }
        return result;
    }

    /**
     * Element-wise vector subtraction: r = a - b.
     */
    public static def subtract(a: Rail[Double], b: Rail[Double]): Rail[Double] {
        val len = Math.min(a.size, b.size);
        val result = new Rail[Double](len);
        for (i in 0..(len - 1)) {
            result(i) = a(i) - b(i);
        }
        return result;
    }

    /**
     * Scale vector by scalar multiplier: r = alpha * v.
     */
    public static def scale(v: Rail[Double], alpha: Double): Rail[Double] {
        val result = new Rail[Double](v.size);
        for (i in 0..(v.size - 1)) {
            result(i) = v(i) * alpha;
        }
        return result;
    }

    /**
     * Normalize vector to unit length.
     */
    public static def normalize(v: Rail[Double]): Rail[Double] {
        val n = norm2(v);
        if (n < 1.0e-12) {
            return new Rail[Double](v.size);
        }
        return scale(v, 1.0 / n);
    }

    /**
     * Compute vector mean and sample variance using two-pass stable algorithm.
     */
    public static def meanAndVariance(v: Rail[Double]): Rail[Double] {
        val result = new Rail[Double](2);
        if (v.size == 0) {
            result(0) = 0.0;
            result(1) = 0.0;
            return result;
        }
        var mean: Double = 0.0;
        for (i in 0..(v.size - 1)) {
            mean += v(i);
        }
        mean = mean / (v.size as Double);
        result(0) = mean;

        if (v.size < 2) {
            result(1) = 0.0;
            return result;
        }

        var sumSq: Double = 0.0;
        for (i in 0..(v.size - 1)) {
            val d = v(i) - mean;
            sumSq += d * d;
        }
        result(1) = sumSq / ((v.size - 1) as Double);
        return result;
    }
}
