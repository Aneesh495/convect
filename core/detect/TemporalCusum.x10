package convect.core.detect;

import convect.core.types.GeoPoint;
import convect.core.types.SensorReading;

/**
 * TemporalCusum implements the Cumulative Sum sequential changepoint algorithm.
 *
 * Designed to detect abrupt shifts in sensor calibration or sudden environmental
 * events (chemical releases, fire outbreaks, seismic precursors).
 * Maintains dual one-sided decision accumulators:
 *   S_hi = max(0, S_hi + (x_t - targetMean - allowance))
 *   S_lo = max(0, S_lo + (targetMean - allowance - x_t))
 *
 * An alarm is raised whenever either accumulator exceeds threshold h.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class TemporalCusum {

    public val allowanceK:Double;
    public val thresholdH:Double;

    public var targetMean:Double;
    public var targetStddev:Double;
    public var sHi:Double;
    public var sLo:Double;
    public var count:Long;

    public def this(allowanceK:Double, thresholdH:Double) {
        this.allowanceK = allowanceK;
        this.thresholdH = thresholdH;
        this.targetMean = 0.0;
        this.targetStddev = 1.0;
        this.sHi = 0.0;
        this.sLo = 0.0;
        this.count = 0L;
    }

    public def this() {
        this(0.5, 4.0);
    }

    /**
     * Calibrate baseline mean and standard deviation from historical observations.
     */
    public def calibrate(mean:Double, stddev:Double):void {
        this.targetMean = mean;
        this.targetStddev = Math.max(1e-6, stddev);
        this.reset();
    }

    public def reset():void {
        this.sHi = 0.0;
        this.sLo = 0.0;
    }

    /**
     * Process an incoming sensor reading. Returns AnomalyResult if threshold exceeded.
     */
    public def update(reading:SensorReading):AnomalyResult {
        this.count++;

        /* Standardize value against calibrated baseline */
        val z = (reading.value - this.targetMean) / this.targetStddev;

        /* Update accumulators */
        this.sHi = Math.max(0.0, this.sHi + z - this.allowanceK);
        this.sLo = Math.max(0.0, this.sLo - z - this.allowanceK);

        var isAnomaly:Boolean = false;
        var maxScore:Double = 0.0;

        if (this.sHi > this.thresholdH) {
            isAnomaly = true;
            maxScore = this.sHi;
            this.sHi = 0.0; /* Reset upon detection */
        } else if (this.sLo > this.thresholdH) {
            isAnomaly = true;
            maxScore = this.sLo;
            this.sLo = 0.0; /* Reset upon detection */
        }

        if (isAnomaly) {
            val confidence = Math.min(0.99, (maxScore / this.thresholdH) * 0.8);
            return AnomalyResult(
                2n, /* TEMPORAL_CHANGEPOINT */
                reading.sensorId,
                reading.location,
                reading.timestamp,
                reading.value,
                this.targetMean,
                maxScore,
                confidence
            );
        }

        /* Sentinel result with score 0 indicating no changepoint */
        return AnomalyResult(0n, reading.sensorId, reading.location, reading.timestamp, 0.0, 0.0, 0.0, 0.0);
    }
}
