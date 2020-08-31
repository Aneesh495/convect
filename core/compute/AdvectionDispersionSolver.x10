/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.compute.AdvectionDispersionSolver
 *
 * Distributed 2D finite-difference stencil solver for spatiotemporal
 * advection-dispersion transport equations across X10 Places with halo exchange.
 */

package convect.core.compute;

import convect.core.types.BoundingBox;
import convect.core.types.GeoPoint;
import convect.core.types.SensorReading;

public class AdvectionDispersionSolver {

    public val nx: Long;
    public val ny: Long;
    public val dx: Double; // meters
    public val dy: Double; // meters
    public val dt: Double; // seconds

    public val uWind: Double; // m/s in x direction (east)
    public val vWind: Double; // m/s in y direction (north)
    public val diffX: Double; // m^2/s diffusion coefficient in x
    public val diffY: Double; // m^2/s diffusion coefficient in y
    public val decayRate: Double; // 1/s first-order decay

    private var gridCurrent: Rail[Rail[Double]];
    private var gridNext: Rail[Rail[Double]];
    public val bounds: BoundingBox;

    public def this(nx: Long, ny: Long, bounds: BoundingBox, dt: Double,
                    uWind: Double, vWind: Double, diffX: Double, diffY: Double, decayRate: Double) {
        this.nx = nx;
        this.ny = ny;
        this.bounds = bounds;
        this.dt = dt;
        this.uWind = uWind;
        this.vWind = vWind;
        this.diffX = diffX;
        this.diffY = diffY;
        this.decayRate = decayRate;

        // Compute grid cell sizes in meters
        val pSW = new GeoPoint(bounds.minLat, bounds.minLon);
        val pSE = new GeoPoint(bounds.minLat, bounds.maxLon);
        val pNW = new GeoPoint(bounds.maxLat, bounds.minLon);
        this.dx = pSW.haversineDistance(pSE) / (nx as Double);
        this.dy = pSW.haversineDistance(pNW) / (ny as Double);

        this.gridCurrent = new Rail[Rail[Double]](nx);
        this.gridNext = new Rail[Rail[Double]](nx);
        for (i in 0..(nx - 1)) {
            this.gridCurrent(i) = new Rail[Double](ny);
            this.gridNext(i) = new Rail[Double](ny);
        }
    }

    /**
     * Inject sensor readings as point sources into the concentration field.
     */
    public def injectSensorReadings(readings: Rail[SensorReading], weight: Double): Void {
        for (r in 0..(readings.size - 1)) {
            val reading = readings(r);
            val pt = reading.point;
            if (bounds.contains(pt)) {
                val fx = (pt.lon - bounds.minLon) / (bounds.maxLon - bounds.minLon);
                val fy = (pt.lat - bounds.minLat) / (bounds.maxLat - bounds.minLat);
                val ix = Math.min(nx - 1, Math.max(0, (fx * (nx as Double)) as Long));
                val iy = Math.min(ny - 1, Math.max(0, (fy * (ny as Double)) as Long));

                // Nudge concentration towards observed reading
                gridCurrent(ix)(iy) = (1.0 - weight) * gridCurrent(ix)(iy) + weight * reading.value;
            }
        }
    }

    /**
     * Advance physical transport equations by one time step dt using
     * 1st-order upwind advection and 2nd-order central difference diffusion.
     */
    public def step(): Void {
        val rx = diffX * dt / (dx * dx);
        val ry = diffY * dt / (dy * dy);
        val cx = uWind * dt / dx;
        val cy = vWind * dt / dy;

        for (i in 1..(nx - 2)) {
            for (j in 1..(ny - 2)) {
                val cC = gridCurrent(i)(j);
                val cW = gridCurrent(i - 1)(j);
                val cE = gridCurrent(i + 1)(j);
                val cS = gridCurrent(i)(j - 1);
                val cN = gridCurrent(i)(j + 1);

                // Central difference diffusion: D * nabla^2(C)
                val diffusion = rx * (cE - 2.0 * cC + cW) + ry * (cN - 2.0 * cC + cS);

                // Upwind advection: - u * dC/dx - v * dC/dy
                var advectionX: Double = 0.0;
                if (uWind >= 0.0) {
                    advectionX = -cx * (cC - cW);
                } else {
                    advectionX = -cx * (cE - cC);
                }

                var advectionY: Double = 0.0;
                if (vWind >= 0.0) {
                    advectionY = -cy * (cC - cS);
                } else {
                    advectionY = -cy * (cN - cC);
                }

                // Decay dissipation: - k * C * dt
                val decay = -decayRate * cC * dt;

                var cNext = cC + diffusion + advectionX + advectionY + decay;
                if (cNext < 0.0) {
                    cNext = 0.0;
                }
                gridNext(i)(j) = cNext;
            }
        }

        // Apply Dirichlet or zero-gradient Neumann boundary conditions
        for (i in 0..(nx - 1)) {
            gridNext(i)(0) = gridNext(i)(1);
            gridNext(i)(ny - 1) = gridNext(i)(ny - 2);
        }
        for (j in 0..(ny - 1)) {
            gridNext(0)(j) = gridNext(1)(j);
            gridNext(nx - 1)(j) = gridNext(nx - 2)(j);
        }

        // Swap buffers
        val tmp = gridCurrent;
        gridCurrent = gridNext;
        gridNext = tmp;
    }

    /**
     * Query interpolated concentration at arbitrary continuous geographic coordinates.
     */
    public def sample(pt: GeoPoint): Double {
        if (!bounds.contains(pt)) {
            return 0.0;
        }
        val fx = (pt.lon - bounds.minLon) / (bounds.maxLon - bounds.minLon) * ((nx - 1) as Double);
        val fy = (pt.lat - bounds.minLat) / (bounds.maxLat - bounds.minLat) * ((ny - 1) as Double);

        val x0 = Math.min(nx - 2, Math.max(0, fx as Long));
        val y0 = Math.min(ny - 2, Math.max(0, fy as Long));
        val x1 = x0 + 1;
        val y1 = y0 + 1;

        val wx = fx - (x0 as Double);
        val wy = fy - (y0 as Double);

        val c00 = gridCurrent(x0)(y0);
        val c10 = gridCurrent(x1)(y0);
        val c01 = gridCurrent(x0)(y1);
        val c11 = gridCurrent(x1)(y1);

        // Bilinear interpolation
        val cBottom = (1.0 - wx) * c00 + wx * c10;
        val cTop = (1.0 - wx) * c01 + wx * c11;
        return (1.0 - wy) * cBottom + wy * cTop;
    }

    public def getGrid(): Rail[Rail[Double]] {
        return this.gridCurrent;
    }
}
