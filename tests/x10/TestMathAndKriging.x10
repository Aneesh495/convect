/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Test Suite: tests.x10.TestMathAndKriging
 *
 * Verifies linear algebra, Cholesky decomposition, empirical variogram fitting,
 * and Ordinary Kriging interpolation under synthetic spatial fields.
 */

package convect.tests.x10;

import convect.core.types.GeoPoint;
import convect.core.types.SensorReading;
import convect.core.math.VectorMath;
import convect.core.math.MatrixOperations;
import convect.core.math.CholeskyDecomposition;
import convect.core.compute.EmpiricalVariogram;
import convect.core.compute.SpatiotemporalKriging;

public class TestMathAndKriging {

    private static def assertCondition(cond: Boolean, msg: String): Void {
        if (!cond) {
            Console.OUT.println("FAILURE: " + msg);
            throw new Exception("Assertion failed: " + msg);
        }
    }

    public static def testVectorMath(): Void {
        val a = new Rail[Double](3);
        a(0) = 1.0; a(1) = 2.0; a(2) = 3.0;
        val b = new Rail[Double](3);
        b(0) = 4.0; b(1) = 5.0; b(2) = 6.0;

        // Dot product: 1*4 + 2*5 + 3*6 = 32
        val dot = VectorMath.dot(a, b);
        assertCondition(Math.abs(dot - 32.0) < 1.0e-6, "VectorMath dot product");

        // Euclidean norm of a: sqrt(1 + 4 + 9) = sqrt(14) ~ 3.741657
        val norm = VectorMath.norm2(a);
        assertCondition(Math.abs(norm - Math.sqrt(14.0)) < 1.0e-6, "VectorMath norm2");

        // Distance: sqrt((1-4)^2 + (2-5)^2 + (3-6)^2) = sqrt(27) ~ 5.19615
        val dist = VectorMath.euclideanDistance(a, b);
        assertCondition(Math.abs(dist - Math.sqrt(27.0)) < 1.0e-6, "VectorMath euclideanDistance");

        Console.OUT.println("PASS: VectorMath tests");
    }

    public static def testCholeskySolver(): Void {
        // Construct 3x3 symmetric positive definite matrix A
        // A = [ 4  12 -16 ]
        //     [ 12 37 -43 ]
        //     [-16 -43 98 ]
        val A = MatrixOperations.zeros(3, 3);
        A(0)(0) = 4.0;  A(0)(1) = 12.0; A(0)(2) = -16.0;
        A(1)(0) = 12.0; A(1)(1) = 37.0; A(1)(2) = -43.0;
        A(2)(0) = -16.0; A(2)(1) = -43.0; A(2)(2) = 98.0;

        val chol = new CholeskyDecomposition(A, 0.0);
        assertCondition(chol.isSuccess(), "Cholesky factorization positive definite");

        // Solve A * x = b for b = [ -8, -13, 107 ]^T
        // Expected solution: x = [ 1, 2, 3 ]^T
        val b = new Rail[Double](3);
        b(0) = -8.0; b(1) = -13.0; b(2) = 107.0;

        val x = chol.solve(b);
        assertCondition(Math.abs(x(0) - 1.0) < 1.0e-4, "Cholesky solve x(0)");
        assertCondition(Math.abs(x(1) - 2.0) < 1.0e-4, "Cholesky solve x(1)");
        assertCondition(Math.abs(x(2) - 3.0) < 1.0e-4, "Cholesky solve x(2)");

        Console.OUT.println("PASS: CholeskyDecomposition tests");
    }

    public static def testKrigingInterpolation(): Void {
        val vario = new EmpiricalVariogram(EmpiricalVariogram.MODEL_EXPONENTIAL, 0.1, 10.0, 50000.0);

        // Generate synthetic grid readings
        val readings = new Rail[SensorReading](4);
        readings(0) = new SensorReading("s0", new GeoPoint(37.77, -122.42), 20.0, 1000L);
        readings(1) = new SensorReading("s1", new GeoPoint(37.78, -122.42), 22.0, 1000L);
        readings(2) = new SensorReading("s2", new GeoPoint(37.77, -122.41), 21.0, 1000L);
        readings(3) = new SensorReading("s3", new GeoPoint(37.78, -122.41), 23.0, 1000L);

        val kriging = new SpatiotemporalKriging(vario, 16);
        val target = new GeoPoint(37.775, -122.415); // Center point
        val result = kriging.predict(target, readings);

        // Center should interpolate close to the average: 21.5
        assertCondition(result.estimate >= 20.0 && result.estimate <= 23.0, "Kriging estimate bounded");
        assertCondition(result.numNeighbors == 4, "Kriging neighbor count");
        assertCondition(result.variance >= 0.0, "Kriging variance non-negative");

        Console.OUT.println("PASS: SpatiotemporalKriging tests");
    }

    public static def main(args: Rail[String]): Void {
        Console.OUT.println("Running TestMathAndKriging...");
        testVectorMath();
        testCholeskySolver();
        testKrigingInterpolation();
        Console.OUT.println("ALL Math and Kriging tests passed successfully!");
    }
}
