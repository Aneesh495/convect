/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.compute.SpatiotemporalKalmanFilter
 *
 * Spatiotemporal Kalman Filter for state estimation, trajectory smoothing,
 * and sensor drift correction across dynamic streaming observations in X10.
 */

package convect.core.compute;

import convect.core.types.GeoPoint;
import convect.core.math.MatrixOperations;
import convect.core.math.CholeskyDecomposition;

public class SpatiotemporalKalmanFilter {

    // State vector: [x, y, vx, vy] in local planar meters
    private var state: Rail[Double];
    // Error covariance matrix (4x4)
    private var P: Rail[Rail[Double]];

    // Process noise covariance Q (4x4)
    private val Q: Rail[Rail[Double]];
    // Measurement noise covariance R (2x2)
    private val R: Rail[Rail[Double]];

    public val origin: GeoPoint;

    public def this(origin: GeoPoint, processNoiseStd: Double, measurementNoiseStd: Double) {
        this.origin = origin;
        this.state = new Rail[Double](4);
        this.P = MatrixOperations.identity(4);
        this.P(0)(0) = 100.0;
        this.P(1)(1) = 100.0;
        this.P(2)(2) = 10.0;
        this.P(3)(3) = 10.0;

        this.Q = MatrixOperations.identity(4);
        val qVal = processNoiseStd * processNoiseStd;
        for (i in 0..3) {
            this.Q(i)(i) = qVal;
        }

        this.R = MatrixOperations.identity(2);
        val rVal = measurementNoiseStd * measurementNoiseStd;
        this.R(0)(0) = rVal;
        this.R(1)(1) = rVal;
    }

    /**
     * Convert geographic coordinates to local tangent plane meters relative to origin.
     */
    private def geoToLocal(pt: GeoPoint): Rail[Double] {
        val xy = new Rail[Double](2);
        val latRad = Math.toRadians(origin.lat);
        val rEarth = 6371000.0; // meters
        xy(0) = Math.toRadians(pt.lon - origin.lon) * rEarth * Math.cos(latRad);
        xy(1) = Math.toRadians(pt.lat - origin.lat) * rEarth;
        return xy;
    }

    /**
     * Convert local tangent plane meters back to geographic coordinates.
     */
    private def localToGeo(x: Double, y: Double): GeoPoint {
        val latRad = Math.toRadians(origin.lat);
        val rEarth = 6371000.0;
        val dLat = Math.toDegrees(y / rEarth);
        val dLon = Math.toDegrees(x / (rEarth * Math.cos(latRad)));
        return new GeoPoint(origin.lat + dLat, origin.lon + dLon);
    }

    /**
     * Predict state and error covariance forward by time interval dt (seconds).
     */
    public def predict(dt: Double): Void {
        // State transition matrix F (4x4)
        val F = MatrixOperations.identity(4);
        F(0)(2) = dt;
        F(1)(3) = dt;

        // State extrapolation: state = F * state
        this.state = MatrixOperations.multiplyVector(F, this.state);

        // Covariance extrapolation: P = F * P * F^T + Q
        val FP = MatrixOperations.multiply(F, this.P);
        val FT = MatrixOperations.transpose(F);
        val FPFT = MatrixOperations.multiply(FP, FT);
        this.P = MatrixOperations.add(FPFT, this.Q);
    }

    /**
     * Update state estimate with new GPS / sensor measurement.
     */
    public def update(measurement: GeoPoint): GeoPoint {
        val z = geoToLocal(measurement);

        // Observation matrix H (2x4)
        val H = MatrixOperations.zeros(2, 4);
        H(0)(0) = 1.0;
        H(1)(1) = 1.0;

        // Innovation y = z - H * x
        val Hx = MatrixOperations.multiplyVector(H, this.state);
        val y = new Rail[Double](2);
        y(0) = z(0) - Hx(0);
        y(1) = z(1) - Hx(1);

        // Innovation covariance S = H * P * H^T + R (2x2)
        val HP = MatrixOperations.multiply(H, this.P);
        val HT = MatrixOperations.transpose(H);
        val HPHT = MatrixOperations.multiply(HP, HT);
        val S = MatrixOperations.add(HPHT, this.R);

        // Invert 2x2 matrix S explicitly
        val det = S(0)(0) * S(1)(1) - S(0)(1) * S(1)(0);
        val invDet = 1.0 / (if (Math.abs(det) < 1.0e-9) 1.0e-9 else det);
        val invS = MatrixOperations.zeros(2, 2);
        invS(0)(0) = S(1)(1) * invDet;
        invS(0)(1) = -S(0)(1) * invDet;
        invS(1)(0) = -S(1)(0) * invDet;
        invS(1)(1) = S(0)(0) * invDet;

        // Near-optimal Kalman gain K = P * H^T * S^-1 (4x2)
        val PHT = MatrixOperations.multiply(this.P, HT);
        val K = MatrixOperations.multiply(PHT, invS);

        // State update: x = x + K * y
        val Ky = MatrixOperations.multiplyVector(K, y);
        for (i in 0..3) {
            this.state(i) += Ky(i);
        }

        // Covariance update: P = (I - K * H) * P
        val KH = MatrixOperations.multiply(K, H);
        val I = MatrixOperations.identity(4);
        val IminusKH = MatrixOperations.zeros(4, 4);
        for (i in 0..3) {
            for (j in 0..3) {
                IminusKH(i)(j) = I(i)(j) - KH(i)(j);
            }
        }
        this.P = MatrixOperations.multiply(IminusKH, this.P);

        // Return smoothed geographic coordinates
        return localToGeo(this.state(0), this.state(1));
    }

    public def getVelocity(): Rail[Double] {
        val v = new Rail[Double](2);
        v(0) = this.state(2);
        v(1) = this.state(3);
        return v;
    }
}
