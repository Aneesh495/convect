/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.query.SpatialJoinExecutor
 *
 * Distributed plane-sweep spatial join between streaming sensor observations
 * and spatial boundary polygons across X10 Places.
 */

package convect.core.query;

import convect.core.types.GeoPoint;
import convect.core.types.SensorReading;
import convect.core.types.BoundingBox;

public class SpatialJoinExecutor {

    /**
     * Pair match record representing a matched sensor reading and polygon.
     */
    public static class JoinMatch {
        public val readingId: String;
        public val polygonIndex: Long;
        public val distance: Double;

        public def this(readingId: String, polygonIndex: Long, distance: Double) {
            this.readingId = readingId;
            this.polygonIndex = polygonIndex;
            this.distance = distance;
        }
    }

    /**
     * Perform local plane-sweep join between a batch of sensor readings and
     * a set of polygon boundaries.
     */
    public static def executeJoin(readings: Rail[SensorReading], polygons: Rail[PolygonIntersection]): Rail[JoinMatch] {
        val numReadings = readings.size;
        val numPolys = polygons.size;

        if (numReadings == 0 || numPolys == 0) {
            return new Rail[JoinMatch](0);
        }

        // Filter and evaluate containment
        // In full PGAS, each Place sweeps its local Hilbert interval
        var matchCount: Long = 0;
        val tempMatches = new Rail[JoinMatch](numReadings * numPolys);

        for (r in 0..(numReadings - 1)) {
            val reading = readings(r);
            val pt = reading.point;

            for (p in 0..(numPolys - 1)) {
                val poly = polygons(p);
                // Step 1: Bounding box filter
                if (poly.bbox.contains(pt)) {
                    // Step 2: Exact point-in-polygon ray-cast refinement
                    if (poly.containsPoint(pt)) {
                        tempMatches(matchCount) = new JoinMatch(reading.sensorId, p, 0.0);
                        matchCount++;
                    }
                }
            }
        }

        // Pack result array
        val results = new Rail[JoinMatch](matchCount);
        for (i in 0..(matchCount - 1)) {
            results(i) = tempMatches(i);
        }
        return results;
    }

    /**
     * Spatial cross-distance join: find all sensor pairs within distance threshold (meters).
     */
    public static def proximityJoin(readings: Rail[SensorReading], maxDistanceMeters: Double): Rail[JoinMatch] {
        val n = readings.size;
        var pairCount: Long = 0;
        val tempPairs = new Rail[JoinMatch](n * n);

        for (i in 0..(n - 1)) {
            val pi = readings(i).point;
            for (j in (i + 1)..(n - 1)) {
                val pj = readings(j).point;
                val dist = pi.haversineDistance(pj);
                if (dist <= maxDistanceMeters) {
                    tempPairs(pairCount) = new JoinMatch(readings(i).sensorId, j, dist);
                    pairCount++;
                }
            }
        }

        val pairs = new Rail[JoinMatch](pairCount);
        for (k in 0..(pairCount - 1)) {
            pairs(k) = tempPairs(k);
        }
        return pairs;
    }
}
