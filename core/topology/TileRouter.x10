package convect.core.topology;

import convect.core.types.GeoPoint;
import convect.core.types.TileId;
import x10.util.ArrayList;

/**
 * TileRouter maps geographic points and TileIds to owning X10 Places.
 *
 * Implements logarithmic binary search over partition boundaries to achieve
 * sub-microsecond routing decisions for incoming streaming observations.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class TileRouter {

    public val partitions:Rail[PlacePartition];
    public val tileOrder:Int;

    public def this(partitions:Rail[PlacePartition], tileOrder:Int) {
        this.partitions = partitions;
        this.tileOrder = tileOrder;
    }

    /**
     * Build an evenly balanced partition topology across N places.
     */
    public static def createBalanced(numPlaces:Long, tileOrder:Int):TileRouter {
        val totalCells = 1L << (2n * tileOrder);
        val cellsPerPlace = totalCells / numPlaces;

        val parts = new Rail[PlacePartition](numPlaces, (p:Long) => {
            val startH = p * cellsPerPlace;
            val endH = if (p == numPlaces - 1L) (totalCells - 1L) else ((p + 1L) * cellsPerPlace - 1L);
            return new PlacePartition(p, startH, endH, tileOrder);
        });

        return new TileRouter(parts, tileOrder);
    }

    /**
     * Map a Hilbert distance index to the owning Place ID.
     */
    public def routeHilbertIndex(hIndex:Long):Long {
        var low:Long = 0L;
        var high:Long = this.partitions.size - 1L;

        while (low <= high) {
            val mid = (low + high) / 2L;
            val part = this.partitions(mid);

            if (hIndex < part.startHilbert) {
                high = mid - 1L;
            } else if (hIndex > part.endHilbert) {
                low = mid + 1L;
            } else {
                return part.placeId;
            }
        }

        /* Fallback to last partition on boundary roundoff */
        return this.partitions(this.partitions.size - 1L).placeId;
    }

    /**
     * Map a TileId to the owning Place ID.
     */
    public def routeTile(tile:TileId):Long {
        var hIdx:Long = tile.hilbertIndex();
        if (tile.order() != this.tileOrder) {
            val diff = this.tileOrder - tile.order();
            hIdx = if (diff > 0n) (hIdx << (2n * diff)) else (hIdx >> (2n * (-diff)));
        }
        return routeHilbertIndex(hIdx);
    }
}
