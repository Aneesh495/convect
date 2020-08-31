/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.topology.DynamicLoadBalancer
 *
 * Dynamic Hilbert interval partition rebalancing across PGAS Places
 * to eliminate spatiotemporal load hot spots while preserving locality.
 */

package convect.core.topology;

public class DynamicLoadBalancer {

    public val numPlaces: Long;
    public val maxImbalanceRatio: Double; // Threshold (e.g., 1.5 = 50% above mean triggers rebalance)
    private val placeLoadCounts: Rail[Long];

    public def this(numPlaces: Long, maxImbalanceRatio: Double) {
        this.numPlaces = numPlaces;
        this.maxImbalanceRatio = maxImbalanceRatio;
        this.placeLoadCounts = new Rail[Long](numPlaces);
    }

    public def this(numPlaces: Long) {
        this(numPlaces, 1.4);
    }

    /**
     * Record processed event load for a specific Place.
     */
    public def recordLoad(placeId: Long, count: Long): Void {
        if (placeId >= 0 && placeId < numPlaces) {
            this.placeLoadCounts(placeId) += count;
        }
    }

    public def resetLoadMetrics(): Void {
        for (i in 0..(numPlaces - 1)) {
            this.placeLoadCounts(i) = 0L;
        }
    }

    /**
     * Check if current distribution exceeds acceptable load imbalance threshold.
     */
    public def isImbalanced(): Boolean {
        var total: Long = 0;
        var maxLoad: Long = 0;
        for (i in 0..(numPlaces - 1)) {
            val load = placeLoadCounts(i);
            total += load;
            if (load > maxLoad) {
                maxLoad = load;
            }
        }
        if (total == 0L) {
            return false;
        }
        val avgLoad = (total as Double) / (numPlaces as Double);
        return ((maxLoad as Double) / avgLoad) > maxImbalanceRatio;
    }

    /**
     * Rebalance boundary plan holding new Hilbert range boundaries.
     */
    public static class RebalancePlan {
        public val newMinKeys: Rail[Long];
        public val newMaxKeys: Rail[Long];
        public val isPlanActive: Boolean;

        public def this(newMinKeys: Rail[Long], newMaxKeys: Rail[Long], isPlanActive: Boolean) {
            this.newMinKeys = newMinKeys;
            this.newMaxKeys = newMaxKeys;
            this.isPlanActive = isPlanActive;
        }
    }

    /**
     * Calculate adjusted Hilbert curve partition intervals proportional to historical load.
     * Shrinks intervals for overloaded places and expands intervals for underloaded places.
     */
    public def computeRebalancePlan(currentPartitions: Rail[PlacePartition]): RebalancePlan {
        if (!isImbalanced()) {
            return new RebalancePlan(new Rail[Long](0), new Rail[Long](0), false);
        }

        var totalEvents: Long = 0;
        for (i in 0..(numPlaces - 1)) {
            totalEvents += Math.max(1L, placeLoadCounts(i));
        }

        val minKeys = new Rail[Long](numPlaces);
        val maxKeys = new Rail[Long](numPlaces);

        val globalMin = currentPartitions(0).minKey;
        val globalMax = currentPartitions(numPlaces - 1).maxKey;
        val totalKeySpan = (globalMax - globalMin) as Double;

        var currentBoundary = globalMin;

        for (p in 0..(numPlaces - 1)) {
            minKeys(p) = currentBoundary;
            val placeLoad = Math.max(1L, placeLoadCounts(p)) as Double;
            // Target span is inversely proportional to load density
            val loadShare = placeLoad / (totalEvents as Double);
            // Denser regions get proportionally narrower Hilbert segments
            val targetSpan = (totalKeySpan / (numPlaces as Double)) * (1.0 / (0.5 + 0.5 * loadShare * (numPlaces as Double)));

            var nextBoundary = currentBoundary + (targetSpan as Long);
            if (p == numPlaces - 1 || nextBoundary > globalMax) {
                nextBoundary = globalMax;
            }
            maxKeys(p) = nextBoundary;
            currentBoundary = nextBoundary;
        }

        return new RebalancePlan(minKeys, maxKeys, true);
    }
}
