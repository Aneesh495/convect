/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.compute.SpatialDbscan
 *
 * Density-based spatial clustering of applications with noise (DBSCAN)
 * for spatiotemporal cluster discovery across X10 Places.
 */

package convect.core.compute;

import convect.core.types.GeoPoint;
import convect.core.types.SensorReading;

public class SpatialDbscan {

    public val epsMeters: Double;
    public val minPts: Long;

    public static val UNVISITED: Long = -1;
    public static val NOISE: Long = -2;

    public def this(epsMeters: Double, minPts: Long) {
        this.epsMeters = epsMeters;
        this.minPts = minPts;
    }

    /**
     * Cluster assignment result for a dataset of spatial readings.
     * Returns an array of cluster IDs (0..k-1, or NOISE = -2).
     */
    public def cluster(readings: Rail[SensorReading]): Rail[Long] {
        val n = readings.size;
        val labels = new Rail[Long](n);
        for (i in 0..(n - 1)) {
            labels(i) = UNVISITED;
        }

        var clusterId: Long = 0;

        for (i in 0..(n - 1)) {
            if (labels(i) != UNVISITED) {
                continue;
            }

            val neighbors = regionQuery(readings, i);
            if (neighbors.size < minPts) {
                labels(i) = NOISE;
            } else {
                expandCluster(readings, labels, i, neighbors, clusterId);
                clusterId++;
            }
        }

        return labels;
    }

    /**
     * Find indices of all points within epsMeters of target index.
     */
    private def regionQuery(readings: Rail[SensorReading], targetIdx: Long): Rail[Long] {
        val n = readings.size;
        val targetPt = readings(targetIdx).point;
        var count: Long = 0;
        val temp = new Rail[Long](n);

        for (i in 0..(n - 1)) {
            val dist = targetPt.haversineDistance(readings(i).point);
            if (dist <= epsMeters) {
                temp(count) = i;
                count++;
            }
        }

        val result = new Rail[Long](count);
        for (k in 0..(count - 1)) {
            result(k) = temp(k);
        }
        return result;
    }

    /**
     * Expand cluster by traversing density-reachable neighbors.
     */
    private def expandCluster(readings: Rail[SensorReading], labels: Rail[Long],
                              coreIdx: Long, initialNeighbors: Rail[Long], clusterId: Long): Void {
        labels(coreIdx) = clusterId;

        // Dynamic queue for frontier expansion
        val queue = new Rail[Long](readings.size * 2);
        var head: Long = 0;
        var tail: Long = initialNeighbors.size;

        for (i in 0..(initialNeighbors.size - 1)) {
            queue(i) = initialNeighbors(i);
        }

        while (head < tail) {
            val curr = queue(head);
            head++;

            if (labels(curr) == NOISE) {
                labels(curr) = clusterId;
            }

            if (labels(curr) != UNVISITED) {
                continue;
            }

            labels(curr) = clusterId;
            val currNeighbors = regionQuery(readings, curr);

            if (currNeighbors.size >= minPts) {
                for (j in 0..(currNeighbors.size - 1)) {
                    val neighborIdx = currNeighbors(j);
                    if (labels(neighborIdx) == UNVISITED || labels(neighborIdx) == NOISE) {
                        if (tail < queue.size) {
                            queue(tail) = neighborIdx;
                            tail++;
                        }
                    }
                }
            }
        }
    }
}
