package convect.core.types;

/**
 * TileExtent associates a TileId with its geographic bounding envelope.
 *
 * Provides spatial containment checks, center calculations, and adjacent tile
 * discovery for distributed stream routing across X10 Places.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public struct TileExtent {

    public val id:TileId;
    public val bbox:BoundingBox;

    public def this(id:TileId, bbox:BoundingBox) {
        this.id = id;
        this.bbox = bbox;
    }

    public def center():GeoPoint {
        return this.bbox.center();
    }

    public def contains(pt:GeoPoint):Boolean {
        return this.bbox.contains(pt);
    }

    public def intersects(otherBox:BoundingBox):Boolean {
        return this.bbox.intersects(otherBox);
    }

    public def toString():String {
        return "TileExtent[id=" + this.id.toString() + ", bbox=" + this.bbox.toString() + "]";
    }

    public def equals(other:TileExtent):Boolean {
        return this.id.equals(other.id) && this.bbox.equals(other.bbox);
    }

    public def hashCode():Int {
        return this.id.hashCode() * 31n + this.bbox.hashCode();
    }
}
