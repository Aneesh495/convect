/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.math.MatrixOperations
 *
 * Dense and symmetric matrix operations for spatiotemporal interpolation,
 * Kriging covariance matrices, and Kalman state transitions in X10.
 */

package convect.core.math;

public class MatrixOperations {

    /**
     * Create a zero-initialized matrix of dimension rows x cols.
     */
    public static def zeros(rows: Long, cols: Long): Rail[Rail[Double]] {
        val m = new Rail[Rail[Double]](rows);
        for (i in 0..(rows - 1)) {
            m(i) = new Rail[Double](cols);
        }
        return m;
    }

    /**
     * Create an identity matrix of size n x n.
     */
    public static def identity(n: Long): Rail[Rail[Double]] {
        val m = zeros(n, n);
        for (i in 0..(n - 1)) {
            m(i)(i) = 1.0;
        }
        return m;
    }

    /**
     * Dense matrix-matrix multiplication: C = A * B.
     */
    public static def multiply(a: Rail[Rail[Double]], b: Rail[Rail[Double]]): Rail[Rail[Double]] {
        val rowsA = a.size;
        val colsA = a(0).size;
        val colsB = b(0).size;

        val c = zeros(rowsA, colsB);
        for (i in 0..(rowsA - 1)) {
            for (k in 0..(colsA - 1)) {
                val aik = a(i)(k);
                for (j in 0..(colsB - 1)) {
                    c(i)(j) += aik * b(k)(j);
                }
            }
        }
        return c;
    }

    /**
     * Matrix-vector multiplication: y = A * x.
     */
    public static def multiplyVector(a: Rail[Rail[Double]], x: Rail[Double]): Rail[Double] {
        val rows = a.size;
        val cols = a(0).size;
        val y = new Rail[Double](rows);

        for (i in 0..(rows - 1)) {
            var sum: Double = 0.0;
            for (j in 0..(cols - 1)) {
                sum += a(i)(j) * x(j);
            }
            y(i) = sum;
        }
        return y;
    }

    /**
     * Transpose a matrix: T(i, j) = A(j, i).
     */
    public static def transpose(a: Rail[Rail[Double]]): Rail[Rail[Double]] {
        val rows = a.size;
        val cols = a(0).size;
        val t = zeros(cols, rows);

        for (i in 0..(rows - 1)) {
            for (j in 0..(cols - 1)) {
                t(j)(i) = a(i)(j);
            }
        }
        return t;
    }

    /**
     * Matrix addition: C = A + B.
     */
    public static def add(a: Rail[Rail[Double]], b: Rail[Rail[Double]]): Rail[Rail[Double]] {
        val rows = a.size;
        val cols = a(0).size;
        val c = zeros(rows, cols);

        for (i in 0..(rows - 1)) {
            for (j in 0..(cols - 1)) {
                c(i)(j) = a(i)(j) + b(i)(j);
            }
        }
        return c;
    }

    /**
     * Matrix scalar scaling: C = alpha * A.
     */
    public static def scale(a: Rail[Rail[Double]], alpha: Double): Rail[Rail[Double]] {
        val rows = a.size;
        val cols = a(0).size;
        val c = zeros(rows, cols);

        for (i in 0..(rows - 1)) {
            for (j in 0..(cols - 1)) {
                c(i)(j) = a(i)(j) * alpha;
            }
        }
        return c;
    }

    /**
     * Symmetrize a square matrix: S = 0.5 * (A + A^T).
     */
    public static def symmetrize(a: Rail[Rail[Double]]): Rail[Rail[Double]] {
        val n = a.size;
        val s = zeros(n, n);
        for (i in 0..(n - 1)) {
            s(i)(i) = a(i)(i);
            for (j in (i + 1)..(n - 1)) {
                val avg = 0.5 * (a(i)(j) + a(j)(i));
                s(i)(j) = avg;
                s(j)(i) = avg;
            }
        }
        return s;
    }
}
