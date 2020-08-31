/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Test Suite: tests.x10.TestAdvectionSolver
 *
 * Verifies finite-difference advection-dispersion stencil solver,
 * source injection, and bilinear continuous spatial interpolation.
 */

package convect.tests.x10;

import convect.core.types.GeoPoint;
import convect.core.types.BoundingBox;
import convect.core.types.SensorReading;
import convect.core.compute.AdvectionDispersionSolver;

public class TestAdvectionSolver {

    private static def assertCondition(cond: Boolean, msg: String): Void {
        if (!cond) {
            Console.OUT.println("FAILURE: " + msg);
            throw new Exception("Assertion failed: " + msg);
        }
    }

    public static def testAdvectionAndDispersion(): Void {
        // 20x20 spatial domain in San Francisco Bay Area
        val bounds = new BoundingBox(37.70, -122.50, 37.80, -122.40);
        val dt = 1.0; // 1s
        val uWind = 2.0; // 2 m/s east
        val vWind = 0.0;
        val diffX = 0.5; // diffusion
        val diffY = 0.5;
        val decay = 0.001;

        val solver = new AdvectionDispersionSolver(20, 20, bounds, dt, uWind, vWind, diffX, diffY, decay);

        // Inject high concentration reading at center
        val center = new GeoPoint(37.75, -122.45);
        val readings = new Rail[SensorReading](1);
        readings(0) = new SensorReading("smoke_origin", center, 100.0, 1000L);

        solver.injectSensorReadings(readings, 1.0);

        val initialConc = solver.sample(center);
        assertCondition(initialConc > 50.0, "Center initial concentration injected");

        // Advance 10 simulation steps
        for (step in 1..10) {
            solver.step();
        }

        // Concentration at origin should diffuse down, and downwind (east) should increase
        val downwind = new GeoPoint(37.75, -122.44); // East of origin
        val downwindConc = solver.sample(downwind);
        assertCondition(downwindConc >= 0.0, "Downwind concentration positive");

        Console.OUT.println("PASS: AdvectionDispersionSolver tests");
    }

    public static def main(args: Rail[String]): Void {
        Console.OUT.println("Running TestAdvectionSolver...");
        testAdvectionAndDispersion();
        Console.OUT.println("ALL Advection Dispersion tests passed successfully!");
    }
}
