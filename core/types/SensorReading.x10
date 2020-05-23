package convect.core.types;

/**
 * SensorReading represents an immutable, georeferenced environmental observation.
 *
 * Implemented as an X10 struct so that millions of streaming observations can be
 * moved across places or packed into flat memory arrays without object header overhead
 * or garbage collector pressure.
 *
 * Each observation carries:
 *   - sensorId: 64-bit hashed identifier for the reporting station
 *   - location: WGS84 GeoPoint coordinate
 *   - timestamp: Unix epoch millisecond timestamp
 *   - metricCode: Integer enumeration code for the observed metric (temperature, PM2.5, etc.)
 *   - value: Double-precision floating point measurement
 *   - quality: 0-100 quality indicator (100 = verified good, <50 = suspect/degraded)
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public struct SensorReading {

    public val sensorId:Long;
    public val location:GeoPoint;
    public val timestamp:Long;
    public val metricCode:Int;
    public val value:Double;
    public val quality:Int;

    /**
     * Constructs a complete sensor reading.
     */
    public def this(sensorId:Long, location:GeoPoint, timestamp:Long,
                    metricCode:Int, value:Double, quality:Int) {
        this.sensorId = sensorId;
        this.location = location;
        this.timestamp = timestamp;
        this.metricCode = metricCode;
        this.value = value;
        this.quality = quality;
    }

    /**
     * Constructs a sensor reading with default quality (100).
     */
    public def this(sensorId:Long, lat:Double, lon:Double, timestamp:Long,
                    metricCode:Int, value:Double) {
        this.sensorId = sensorId;
        this.location = GeoPoint(lat, lon);
        this.timestamp = timestamp;
        this.metricCode = metricCode;
        this.value = value;
        this.quality = 100n;
    }

    /**
     * Check if observation meets confidence threshold.
     */
    public def isReliable(minQuality:Int):Boolean {
        return this.quality >= minQuality;
    }

    /**
     * Haversine distance in meters to another reading location.
     */
    public def distanceTo(other:SensorReading):Double {
        return this.location.distanceTo(other.location);
    }

    public def toString():String {
        return "SensorReading(id=" + this.sensorId + ", loc=" + this.location.toString() +
               ", t=" + this.timestamp + ", m=" + this.metricCode + ", val=" + this.value +
               ", q=" + this.quality + ")";
    }

    public def equals(other:SensorReading):Boolean {
        return this.sensorId == other.sensorId &&
               this.location.equals(other.location) &&
               this.timestamp == other.timestamp &&
               this.metricCode == other.metricCode &&
               this.value == other.value &&
               this.quality == other.quality;
    }

    public def hashCode():Int {
        var h:Long = this.sensorId;
        h = h * 31n + this.location.hashCode();
        h = h * 31n + this.timestamp;
        h = h * 31n + (this.metricCode as Long);
        h = h * 31n + Double.doubleToLongBits(this.value);
        return (h ^ (h >> 32)) as Int;
    }
}
