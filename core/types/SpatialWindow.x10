package convect.core.types;

/**
 * SpatialWindow defines a bounded 3D spatiotemporal volume [lat, lon, time].
 *
 * Used as the fundamental windowing slice for stream aggregations, spatial joins,
 * and distributed anomaly detection across clustered Places.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public struct SpatialWindow {

    public val windowId:Long;
    public val bbox:BoundingBox;
    public val startTime:Long;
    public val endTime:Long;

    public def this(windowId:Long, bbox:BoundingBox, startTime:Long, endTime:Long) {
        this.windowId = windowId;
        this.bbox = bbox;
        this.startTime = startTime;
        this.endTime = endTime;
    }

    public def durationMs():Long {
        return this.endTime - this.startTime;
    }

    public def contains(reading:SensorReading):Boolean {
        return reading.timestamp >= this.startTime &&
               reading.timestamp < this.endTime &&
               this.bbox.contains(reading.location);
    }

    public def overlaps(other:SpatialWindow):Boolean {
        val temporalOverlap = (this.startTime < other.endTime) && (this.endTime > other.startTime);
        return temporalOverlap && this.bbox.intersects(other.bbox);
    }

    public def toString():String {
        return "SpatialWindow[id=" + this.windowId + ", t=[" + this.startTime + ".." +
               this.endTime + "], bbox=" + this.bbox.toString() + "]";
    }

    public def equals(other:SpatialWindow):Boolean {
        return this.windowId == other.windowId &&
               this.startTime == other.startTime &&
               this.endTime == other.endTime &&
               this.bbox.equals(other.bbox);
    }

    public def hashCode():Int {
        var h:Long = this.windowId;
        h = h * 31n + this.startTime;
        h = h * 31n + this.endTime;
        return (h ^ (h >> 32)) as Int;
    }
}
