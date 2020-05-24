package convect.core.types;

/**
 * TileId uniquely identifies a discrete geographic partition in the global grid.
 *
 * Encodes the hierarchical resolution level (order) and the 1D Hilbert index
 * within a packed 64-bit integer representation:
 *   - High 8 bits: Hilbert curve order (resolution depth 1 to 28)
 *   - Low 56 bits: Hilbert distance index along the space-filling curve
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public struct TileId {

    public val packedId:Long;

    public def this(order:Int, hilbertIndex:Long) {
        val o = (order as Long) & 0xFFL;
        val idx = hilbertIndex & 0x00FFFFFFFFFFFFFFL;
        this.packedId = (o << 56) | idx;
    }

    public def this(packedId:Long) {
        this.packedId = packedId;
    }

    public def order():Int {
        return ((this.packedId >> 56) & 0xFFL) as Int;
    }

    public def hilbertIndex():Long {
        return this.packedId & 0x00FFFFFFFFFFFFFFL;
    }

    /**
     * Derives parent tile identifier at one lower resolution level.
     */
    public def parent():TileId {
        val ord = this.order();
        if (ord <= 1n) return this;
        val parentIdx = this.hilbertIndex() >> 2;
        return TileId(ord - 1n, parentIdx);
    }

    public def toString():String {
        return "TileId(order=" + this.order() + ", idx=" + this.hilbertIndex() + ")";
    }

    public def equals(other:TileId):Boolean {
        return this.packedId == other.packedId;
    }

    public def hashCode():Int {
        return (this.packedId ^ (this.packedId >> 32)) as Int;
    }
}
