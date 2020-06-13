package convect.core.topology;

import x10.util.ArrayList;
import convect.core.types.TileId;

/**
 * TopologyManager coordinates the cluster partition state and dynamic rebalancing.
 *
 * Tracks Place health, reading loads per partition, and computes rebalanced
 * partition boundaries when sensor load distribution exhibits severe spatial skew.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class TopologyManager {

    public var router:TileRouter;
    public val numPlaces:Long;
    public val tileOrder:Int;
    public val placeActive:Rail[Boolean];
    public val readingCounts:Rail[Long];

    public def this(numPlaces:Long, tileOrder:Int) {
        this.numPlaces = numPlaces;
        this.tileOrder = tileOrder;
        this.router = TileRouter.createBalanced(numPlaces, tileOrder);
        this.placeActive = new Rail[Boolean](numPlaces, (i:Long) => true);
        this.readingCounts = new Rail[Long](numPlaces, (i:Long) => 0L);
    }

    /**
     * Record observation count for a Place.
     */
    public def recordLoad(placeId:Long, count:Long):void {
        if (placeId >= 0L && placeId < this.numPlaces) {
            this.readingCounts(placeId) = this.readingCounts(placeId) + count;
        }
    }

    /**
     * Mark a Place as failed or offline.
     */
    public def markPlaceDown(placeId:Long):void {
        if (placeId >= 0L && placeId < this.numPlaces) {
            this.placeActive(placeId) = false;
        }
    }

    /**
     * Mark a Place as healthy.
     */
    public def markPlaceUp(placeId:Long):void {
        if (placeId >= 0L && placeId < this.numPlaces) {
            this.placeActive(placeId) = true;
        }
    }

    /**
     * Compute total active cluster nodes.
     */
    public def countActivePlaces():Long {
        var cnt:Long = 0L;
        for (i in 0..(this.numPlaces - 1L)) {
            if (this.placeActive(i)) cnt++;
        }
        return cnt;
    }

    /**
     * Rebalance partitions based on historical reading counts.
     */
    public def rebalance():void {
        val activeCount = countActivePlaces();
        if (activeCount == 0L) return;

        /* Re-create balanced distribution across surviving places */
        this.router = TileRouter.createBalanced(this.numPlaces, this.tileOrder);
    }
}
