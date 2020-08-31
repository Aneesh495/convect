/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.math.CholeskyDecomposition
 *
 * Cholesky factorization (A = L * L^T) and linear system solver for
 * positive definite spatiotemporal covariance matrices in X10.
 */

package convect.core.math;

public class CholeskyDecomposition {

    private val n: Long;
    private val L: Rail[Rail[Double]];
    private var isPositiveDefinite: Boolean;

    public def this(a: Rail[Rail[Double]], jitter: Double) {
        this.n = a.size;
        this.L = MatrixOperations.zeros(n, n);
        this.isPositiveDefinite = true;
        this.decompose(a, jitter);
    }

    public def this(a: Rail[Rail[Double]]) {
        this(a, 1.0e-8);
    }

    /**
     * Perform Banachiewicz / Cholesky factorization with diagonal jitter regularization.
     */
    private def decompose(a: Rail[Rail[Double]], jitter: Double): Void {
        for (i in 0..(n - 1)) {
            for (j in 0..i) {
                var sum: Double = 0.0;
                for (k in 0..(j - 1)) {
                    sum += L(i)(k) * L(j)(k);
                }

                if (i == j) {
                    val d = a(i)(i) + jitter - sum;
                    if (d <= 0.0) {
                        this.isPositiveDefinite = false;
                        L(i)(i) = 1.0e-6; // Fallback for numerical stability
                    } else {
                        L(i)(i) = Math.sqrt(d);
                    }
                } else {
                    if (Math.abs(L(j)(j)) < 1.0e-12) {
                        L(i)(j) = 0.0;
                    } else {
                        L(i)(j) = (a(i)(j) - sum) / L(j)(j);
                    }
                }
            }
        }
    }

    public def isSuccess(): Boolean {
        return this.isPositiveDefinite;
    }

    public def getL(): Rail[Rail[Double]] {
        return this.L;
    }

    /**
     * Solve A * x = b via forward substitution (L * y = b) followed by
     * back substitution (L^T * x = y).
     */
    public def solve(b: Rail[Double]): Rail[Double] {
        val y = new Rail[Double](n);

        // Forward substitution: L * y = b
        for (i in 0..(n - 1)) {
            var sum: Double = 0.0;
            for (k in 0..(i - 1)) {
                sum += L(i)(k) * y(k);
            }
            y(i) = (b(i) - sum) / L(i)(i);
        }

        // Back substitution: L^T * x = y
        val x = new Rail[Double](n);
        var i: Long = n - 1;
        while (i >= 0) {
            var sum: Double = 0.0;
            for (k in (i + 1)..(n - 1)) {
                sum += L(k)(i) * x(k);
            }
            x(i) = (y(i) - sum) / L(i)(i);
            i--;
        }

        return x;
    }

    /**
     * Solve A * X = B for matrix right-hand side B.
     */
    public def solveMatrix(B: Rail[Rail[Double]]): Rail[Rail[Double]] {
        val cols = B(0).size;
        val X = MatrixOperations.zeros(n, cols);

        for (j in 0..(cols - 1)) {
            val colB = new Rail[Double](n);
            for (i in 0..(n - 1)) {
                colB(i) = B(i)(j);
            }
            val colX = solve(colB);
            for (i in 0..(n - 1)) {
                X(i)(j) = colX(i);
            }
        }
        return X;
    }
}
