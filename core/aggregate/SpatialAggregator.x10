/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.aggregate.SpatialAggregator
 *
 * Distributed spatiotemporal window aggregator computing real-time
 * spatial statistics, centroids, bounding hulls, and variance in X10.
 */

package convect.core.aggregate;

import convect.core.types.GeoPoint;
import convect.core.types.BoundingBox;
import convect.core.types.SensorReading;

public class SpatialAggregator {

    public var count: Long;
    public var minVal: Double;
    public var maxVal: Double;
    public var meanVal: Double;
    public var m2Val: Double; // For Welford variance

    public var centroidLat: Double;
    public var centroidLon: Double;

    public var minLat: Double;
    public var maxLat: Double;
    public var minLon: Double;
    public var maxLon: Double;

    public def this() {
        this.reset();
    }

    public def reset(): Void {
        this.count = 0;
        this.minVal = Double.MAX_VALUE;
        this.maxVal = -Double.MAX_VALUE;
        this.meanVal = 0.0;
        this.m2Val = 0.0;

        this.centroidLat = 0.0;
        this.centroidLon = 0.0;

        this.minLat = 90.0;
        this.maxLat = -90.0;
        this.minLon = 180.0;
        this.maxLon = -180.0;
    }

    /**
     * Ingest a new sensor reading into the running spatial summary.
     */
    public def add(reading: SensorReading): Void {
        this.count++;
        val v = reading.value;

        if (v < this.minVal) this.minVal = v;
        if (v > this.maxVal) this.maxVal = v;

        // Welford online mean and variance accumulation
        val delta = v - this.meanVal;
        this.meanVal += delta / (this.count as Double);
        val delta2 = v - this.meanVal;
        this.m2Val += delta * delta2;

        // Online centroid calculation
        val pt = reading.point;
        this.centroidLat += (pt.lat - this.centroidLat) / (this.count as Double);
        this.centroidLon += (pt.lon - this.centroidLon) / (this.count as Double);

        // Bounding box envelope expansion
        if (pt.lat < this.minLat) this.minLat = pt.lat;
        if (pt.lat > this.maxLat) this.maxLat = pt.lat;
        if (pt.lon < this.minLon) this.minLon = pt.lon;
        if (pt.lon > this.maxLon) this.maxLon = pt.lon;
    }

    /**
     * Merge another partial spatial aggregator summary into this one.
     */
    public def merge(other: SpatialAggregator): Void {
        if (other.count == 0) {
            return;
        }
        if (this.count == 0) {
            this.count = other.count;
            this.minVal = other.minVal;
            this.maxVal = other.maxVal;
            this.meanVal = other.meanVal;
            this.m2Val = other.m2Val;
            this.centroidLat = other.centroidLat;
            this.centroidLon = other.centroidLon;
            this.minLat = other.minLat;
            this.maxLat = other.maxLat;
            this.minLon = other.minLon;
            this.maxLon = other.maxLon;
            return;
        }

        val totalCount = this.count + other.count;
        val deltaMean = other.meanVal - this.meanVal;
        val combinedMean = (this.meanVal * (this.count as Double) + other.meanVal * (other.count as Double)) / (totalCount as Double);

        this.m2Val = this.m2Val + other.m2Val + deltaMean * deltaMean * ((this.count * other.count) as Double) / (totalCount as Double);
        this.meanVal = combinedMean;

        if (other.minVal < this.minVal) this.minVal = other.minVal;
        if (other.maxVal > this.maxVal) this.maxVal = other.maxVal;

        // Centroid combine
        this.centroidLat = (this.centroidLat * (this.count as Double) + other.centroidLat * (other.count as Double)) / (totalCount as Double);
        this.centroidLon = (this.centroidLon * (this.count as Double) + other.centroidLon * (other.count as Double)) / (totalCount as Double);

        // Envelope union
        if (other.minLat < this.minLat) this.minLat = other.minLat;
        if (other.maxLat > this.maxLat) this.maxLat = other.maxLat;
        if (other.minLon < this.minLon) this.minLon = other.minLon;
        if (other.maxLon > this.maxLon) this.maxLon = other.maxLon;

        this.count = totalCount;
    }

    public def getVariance(): Double {
        if (this.count < 2) return 0.0;
        return this.m2Val / ((this.count - 1) as Double);
    }

    public def getStdDev(): Double {
        return Math.sqrt(this.getVariance());
    }

    public def getCentroid(): GeoPoint {
        return new GeoPoint(this.centroidLat, this.centroidLon);
    }

    public def getEnvelope(): BoundingBox {
        if (this.count == 0) {
            return new BoundingBox(0.0, 0.0, 0.0, 0.0);
        }
        return new BoundingBox(this.minLat, this.minLon, this.maxLat, this.maxLon);
    }
}
