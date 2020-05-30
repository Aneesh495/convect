package convect.core.topology;

import convect.core.types.TileId;
import convect.core.types.GeoPoint;
import x10.util.ArrayList;

/**
 * PlacePartition represents the set of spatial tiles assigned to a single X10 Place.
 *
 * Utilizes contiguous intervals along the Hilbert space-filling curve to preserve
 * 2D spatial locality. Because the Hilbert curve maps nearby 2D regions into adjacent
 * 1D intervals, partitioning the curve into contiguous segments guarantees that each
 * Place owns geographically clustered tiles with compact boundary perimeters.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class PlacePartition {

    public val placeId:Long;
    public val startHilbert:Long;
    public val endHilbert:Long;
    public val tileOrder:Int;
    public var totalReadingsProcessed:Long;

    public def this(placeId:Long, startHilbert:Long, endHilbert:Long, tileOrder:Int) {
        this.placeId = placeId;
        this.startHilbert = startHilbert;
        this.endHilbert = endHilbert;
        this.tileOrder = tileOrder;
        this.totalReadingsProcessed = 0L;
    }

    /**
     * Test whether a Hilbert distance index falls within this partition's range.
     */
    public def ownsIndex(hIndex:Long):Boolean {
        return hIndex >= this.startHilbert && hIndex <= this.endHilbert;
    }

    /**
     * Test whether this partition owns the specified TileId.
     */
    public def ownsTile(tile:TileId):Boolean {
        if (tile.order() != this.tileOrder) {
            /* If orders differ, scale Hilbert index to match this partition's resolution */
            val diff = this.tileOrder - tile.order();
            val scaledIndex = if (diff > 0n) (tile.hilbertIndex() << (2n * diff)) else (tile.hilbertIndex() >> (2n * (-diff)));
            return ownsIndex(scaledIndex);
        }
        return ownsIndex(tile.hilbertIndex());
    }

    /**
     * Record an ingested reading for load tracking.
     */
    public def recordIngestion():void {
        this.totalReadingsProcessed++;
    }

    public def toString():String {
        return "PlacePartition(place=" + this.placeId + ", range=[" +
               this.startHilbert + ".." + this.endHilbert + "], order=" + this.tileOrder +
               ", readings=" + this.totalReadingsProcessed + ")";
    }
}
