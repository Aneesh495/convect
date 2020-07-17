package convect.core.detect;

import convect.core.types.GeoPoint;

/**
 * AnomalyResult records a detected spatiotemporal anomaly.
 *
 * Captures anomaly severity, detection strategy identifier, spatial location,
 * baseline expected value, observed value, and confidence score.
 *
 * Anomaly categories:
 *   1 = SPATIAL_OUTLIER (Local Outlier Factor neighborhood divergence)
 *   2 = TEMPORAL_CHANGEPOINT (CUSUM abrupt mean/variance shift)
 *   3 = SPATIAL_AUTOCORRELATION_BREAKDOWN (Moran's I local spatial outlier)
 *   4 = MULTIVARIATE_CORRELATION_COLLAPSE (Divergence between historically correlated metrics)
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public struct AnomalyResult {

    public val anomalyType:Int;
    public val sensorId:Long;
    public val location:GeoPoint;
    public val timestamp:Long;
    public val observedValue:Double;
    public val expectedValue:Double;
    public val score:Double;
    public val confidence:Double;

    public def this(anomalyType:Int, sensorId:Long, location:GeoPoint, timestamp:Long,
                    observedValue:Double, expectedValue:Double, score:Double, confidence:Double) {
        this.anomalyType = anomalyType;
        this.sensorId = sensorId;
        this.location = location;
        this.timestamp = timestamp;
        this.observedValue = observedValue;
        this.expectedValue = expectedValue;
        this.score = score;
        this.confidence = confidence;
    }

    public def typeName():String {
        switch (this.anomalyType) {
            case 1n: return "SPATIAL_OUTLIER";
            case 2n: return "TEMPORAL_CHANGEPOINT";
            case 3n: return "SPATIAL_AUTOCORRELATION_BREAKDOWN";
            case 4n: return "MULTIVARIATE_CORRELATION_COLLAPSE";
            default: return "UNKNOWN_ANOMALY";
        }
    }

    public def toString():String {
        return "AnomalyResult(type=" + typeName() + ", sensor=" + this.sensorId +
               ", loc=" + this.location.toString() + ", t=" + this.timestamp +
               ", obs=" + this.observedValue + ", exp=" + this.expectedValue +
               ", score=" + this.score + ", conf=" + (this.confidence * 100.0) + "%)";
    }
}
