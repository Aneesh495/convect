package convect.core.types;

/**
 * BoundingBox represents an axis-aligned geographic rectangle on Earth's surface.
 *
 * This is the fundamental spatial query primitive in convect. Every tile has a
 * bounding box that defines its geographic extent, and range queries are
 * expressed as bounding box intersections.
 *
 * The box is defined by its southwest (min) and northeast (max) corners:
 *
 *     (maxLat, minLon) -------- (maxLat, maxLon)
 *          |                         |
 *          |        BoundingBox      |
 *          |                         |
 *     (minLat, minLon) -------- (minLat, maxLon)
 *
 * Anti-meridian crossing (where minLon > maxLon, e.g., a box spanning from
 * 170E to 170W) is NOT supported in this version. Queries that cross the
 * anti-meridian should be split into two boxes by the caller.
 *
 * Like GeoPoint, this is a struct to avoid heap allocation for a type that
 * is created and copied frequently during spatial filtering.
 */
public struct BoundingBox {

    // -----------------------------------------------------------------------
    // Fields
    // -----------------------------------------------------------------------

    /** Southern boundary (minimum latitude, degrees). */
    public val minLat:Double;

    /** Western boundary (minimum longitude, degrees). */
    public val minLon:Double;

    /** Northern boundary (maximum latitude, degrees). */
    public val maxLat:Double;

    /** Eastern boundary (maximum longitude, degrees). */
    public val maxLon:Double;

    // -----------------------------------------------------------------------
    // Constructors
    // -----------------------------------------------------------------------

    /**
     * Create a bounding box from corner coordinates.
     *
     * @param minLat Southern boundary
     * @param minLon Western boundary
     * @param maxLat Northern boundary
     * @param maxLon Eastern boundary
     */
    public def this(minLat:Double, minLon:Double, maxLat:Double, maxLon:Double) {
        this.minLat = minLat;
        this.minLon = minLon;
        this.maxLat = maxLat;
        this.maxLon = maxLon;
    }

    /**
     * Create a bounding box centered on a point with given half-extents.
     * Useful for building search windows around a sensor location.
     *
     * @param center The center point
     * @param halfLatDeg Half-height in degrees of latitude
     * @param halfLonDeg Half-width in degrees of longitude
     * @return A bounding box centered on the given point
     */
    public static def around(center:GeoPoint, halfLatDeg:Double, halfLonDeg:Double):BoundingBox {
        return BoundingBox(
            Math.max(center.lat - halfLatDeg, GeoPoint.MIN_LAT),
            Math.max(center.lon - halfLonDeg, GeoPoint.MIN_LON),
            Math.min(center.lat + halfLatDeg, GeoPoint.MAX_LAT),
            Math.min(center.lon + halfLonDeg, GeoPoint.MAX_LON)
        );
    }

    /**
     * Create the smallest bounding box that contains all given points.
     * Returns a degenerate (zero-area) box if only one point is given.
     *
     * @param points Array of geographic points
     * @return The minimum enclosing bounding box
     */
    public static def enclosing(points:Rail[GeoPoint]):BoundingBox {
        var minLat:Double = Double.MAX_VALUE;
        var minLon:Double = Double.MAX_VALUE;
        var maxLat:Double = -Double.MAX_VALUE;
        var maxLon:Double = -Double.MAX_VALUE;

        for (i in 0..(points.size - 1)) {
            val p = points(i);
            if (p.lat < minLat) minLat = p.lat;
            if (p.lon < minLon) minLon = p.lon;
            if (p.lat > maxLat) maxLat = p.lat;
            if (p.lon > maxLon) maxLon = p.lon;
        }

        return BoundingBox(minLat, minLon, maxLat, maxLon);
    }

    /**
     * Create a bounding box representing the entire globe.
     *
     * @return A box covering [-90, -180] to [90, 180]
     */
    public static def global():BoundingBox {
        return BoundingBox(
            GeoPoint.MIN_LAT, GeoPoint.MIN_LON,
            GeoPoint.MAX_LAT, GeoPoint.MAX_LON
        );
    }

    // -----------------------------------------------------------------------
    // Geometric Properties
    // -----------------------------------------------------------------------

    /**
     * Compute the width of this box in degrees of longitude.
     */
    public def widthDeg():Double {
        return this.maxLon - this.minLon;
    }

    /**
     * Compute the height of this box in degrees of latitude.
     */
    public def heightDeg():Double {
        return this.maxLat - this.minLat;
    }

    /**
     * Compute the area of this box in square degrees.
     * This is NOT a true geodetic area (square degrees vary in real area
     * with latitude), but it is useful for comparing boxes at similar
     * latitudes and for R-tree split heuristics.
     */
    public def areaDeg2():Double {
        return widthDeg() * heightDeg();
    }

    /**
     * Compute the approximate area in square meters.
     * Uses the trapezoidal approximation: the average width at the center
     * latitude times the height converted to meters.
     *
     * @return Approximate area in square meters
     */
    public def areaM2():Double {
        val centerLat = (this.minLat + this.maxLat) / 2.0;
        val latRadians = centerLat * (Math.PI / 180.0);

        // One degree of latitude is approximately 111,320 meters
        val mPerDegLat = 111320.0;
        // One degree of longitude varies with latitude
        val mPerDegLon = 111320.0 * Math.cos(latRadians);

        return (heightDeg() * mPerDegLat) * (widthDeg() * mPerDegLon);
    }

    /**
     * Compute the perimeter (margin) of this box in degrees.
     * Used by the R-tree split algorithm to choose the axis that
     * minimizes the total margin of the resulting nodes.
     */
    public def marginDeg():Double {
        return 2.0 * (widthDeg() + heightDeg());
    }

    /**
     * Get the center point of this bounding box.
     */
    public def center():GeoPoint {
        return GeoPoint(
            (this.minLat + this.maxLat) / 2.0,
            (this.minLon + this.maxLon) / 2.0
        );
    }

    /**
     * Get the southwest corner of this box.
     */
    public def southwest():GeoPoint {
        return GeoPoint(this.minLat, this.minLon);
    }

    /**
     * Get the northeast corner of this box.
     */
    public def northeast():GeoPoint {
        return GeoPoint(this.maxLat, this.maxLon);
    }

    /**
     * Get the northwest corner of this box.
     */
    public def northwest():GeoPoint {
        return GeoPoint(this.maxLat, this.minLon);
    }

    /**
     * Get the southeast corner of this box.
     */
    public def southeast():GeoPoint {
        return GeoPoint(this.minLat, this.maxLon);
    }

    // -----------------------------------------------------------------------
    // Spatial Predicates
    // -----------------------------------------------------------------------

    /**
     * Test whether this box contains a given point (inclusive of boundaries).
     *
     * @param point The point to test
     * @return true if the point is inside or on the boundary
     */
    public def contains(point:GeoPoint):Boolean {
        return point.lat >= this.minLat && point.lat <= this.maxLat
            && point.lon >= this.minLon && point.lon <= this.maxLon;
    }

    /**
     * Test whether this box fully contains another box.
     *
     * @param other The box to test
     * @return true if other is entirely within this box
     */
    public def containsBox(other:BoundingBox):Boolean {
        return other.minLat >= this.minLat && other.maxLat <= this.maxLat
            && other.minLon >= this.minLon && other.maxLon <= this.maxLon;
    }

    /**
     * Test whether this box intersects (overlaps with) another box.
     * Two boxes intersect if they share any area, including touching edges.
     *
     * @param other The box to test
     * @return true if the boxes overlap
     */
    public def intersects(other:BoundingBox):Boolean {
        // Two boxes do NOT intersect if one is entirely above, below,
        // left of, or right of the other.
        if (this.maxLat < other.minLat || this.minLat > other.maxLat) return false;
        if (this.maxLon < other.minLon || this.minLon > other.maxLon) return false;
        return true;
    }

    /**
     * Compute the intersection of this box with another.
     * Returns null if the boxes do not intersect.
     *
     * The caller must check intersects() first or handle the null case,
     * since X10 structs cannot be null. We return a zero-area sentinel
     * box with all coordinates set to 0.0 if there is no intersection,
     * and the caller should check via isDegenerate().
     *
     * @param other The box to intersect with
     * @return The intersection box, or a degenerate box if no overlap
     */
    public def intersection(other:BoundingBox):BoundingBox {
        if (!this.intersects(other)) {
            return BoundingBox(0.0, 0.0, 0.0, 0.0);
        }
        return BoundingBox(
            Math.max(this.minLat, other.minLat),
            Math.max(this.minLon, other.minLon),
            Math.min(this.maxLat, other.maxLat),
            Math.min(this.maxLon, other.maxLon)
        );
    }

    /**
     * Check whether this box is degenerate (zero area).
     */
    public def isDegenerate():Boolean {
        return this.minLat >= this.maxLat || this.minLon >= this.maxLon;
    }

    // -----------------------------------------------------------------------
    // Box Operations
    // -----------------------------------------------------------------------

    /**
     * Compute the union of this box with another (the smallest box that
     * contains both).
     *
     * @param other The box to union with
     * @return The union bounding box
     */
    public def union(other:BoundingBox):BoundingBox {
        return BoundingBox(
            Math.min(this.minLat, other.minLat),
            Math.min(this.minLon, other.minLon),
            Math.max(this.maxLat, other.maxLat),
            Math.max(this.maxLon, other.maxLon)
        );
    }

    /**
     * Compute the enlargement in area that would result from extending
     * this box to include the given point.
     *
     * This is a key metric in R-tree insertion: we choose the subtree
     * whose bounding box requires the least enlargement to accommodate
     * the new entry.
     *
     * @param point The point to hypothetically include
     * @return The increase in area (in square degrees)
     */
    public def enlargementToInclude(point:GeoPoint):Double {
        val newMinLat = Math.min(this.minLat, point.lat);
        val newMinLon = Math.min(this.minLon, point.lon);
        val newMaxLat = Math.max(this.maxLat, point.lat);
        val newMaxLon = Math.max(this.maxLon, point.lon);
        val newArea = (newMaxLat - newMinLat) * (newMaxLon - newMinLon);
        return newArea - this.areaDeg2();
    }

    /**
     * Compute the enlargement in area that would result from extending
     * this box to contain another box.
     *
     * @param other The box to hypothetically include
     * @return The increase in area (in square degrees)
     */
    public def enlargementToIncludeBox(other:BoundingBox):Double {
        val enlarged = this.union(other);
        return enlarged.areaDeg2() - this.areaDeg2();
    }

    /**
     * Compute the overlap area between this box and another.
     * Used by the R*-tree split algorithm to minimize overlap.
     *
     * @param other The box to compute overlap with
     * @return Overlap area in square degrees, or 0 if no overlap
     */
    public def overlapArea(other:BoundingBox):Double {
        val interMinLat = Math.max(this.minLat, other.minLat);
        val interMinLon = Math.max(this.minLon, other.minLon);
        val interMaxLat = Math.min(this.maxLat, other.maxLat);
        val interMaxLon = Math.min(this.maxLon, other.maxLon);

        if (interMinLat >= interMaxLat || interMinLon >= interMaxLon) {
            return 0.0;
        }
        return (interMaxLat - interMinLat) * (interMaxLon - interMinLon);
    }

    /**
     * Expand this box by a given margin in all directions (in degrees).
     *
     * @param marginDeg The margin to add in each direction
     * @return The expanded box
     */
    public def expand(marginDeg:Double):BoundingBox {
        return BoundingBox(
            Math.max(this.minLat - marginDeg, GeoPoint.MIN_LAT),
            Math.max(this.minLon - marginDeg, GeoPoint.MIN_LON),
            Math.min(this.maxLat + marginDeg, GeoPoint.MAX_LAT),
            Math.min(this.maxLon + marginDeg, GeoPoint.MAX_LON)
        );
    }

    /**
     * Compute the minimum distance from this box to a point.
     * Returns 0 if the point is inside the box.
     * Uses degree-based Euclidean distance (fast approximate).
     *
     * @param point The point to measure distance to
     * @return Minimum distance in degrees (approximate)
     */
    public def minDistanceTo(point:GeoPoint):Double {
        // Clamp the point to the nearest edge of the box
        val clampedLat = Math.max(this.minLat, Math.min(this.maxLat, point.lat));
        val clampedLon = Math.max(this.minLon, Math.min(this.maxLon, point.lon));

        val dLat = point.lat - clampedLat;
        val dLon = point.lon - clampedLon;
        return Math.sqrt(dLat * dLat + dLon * dLon);
    }

    // -----------------------------------------------------------------------
    // Subdivision (for quadtree-style partitioning)
    // -----------------------------------------------------------------------

    /**
     * Split this box into four quadrants: NW, NE, SW, SE.
     * Used by the tile topology system to subdivide geographic space.
     *
     * @return Array of four bounding boxes [NW, NE, SW, SE]
     */
    public def quadrants():Rail[BoundingBox] {
        val midLat = (this.minLat + this.maxLat) / 2.0;
        val midLon = (this.minLon + this.maxLon) / 2.0;

        return new Rail[BoundingBox](4, (i:Long) => {
            switch (i as Int) {
                case 0n: return BoundingBox(midLat, this.minLon, this.maxLat, midLon); // NW
                case 1n: return BoundingBox(midLat, midLon, this.maxLat, this.maxLon); // NE
                case 2n: return BoundingBox(this.minLat, this.minLon, midLat, midLon); // SW
                case 3n: return BoundingBox(this.minLat, midLon, midLat, this.maxLon); // SE
                default: return BoundingBox(0.0, 0.0, 0.0, 0.0); // unreachable
            }
        });
    }

    // -----------------------------------------------------------------------
    // Validation
    // -----------------------------------------------------------------------

    /**
     * Check whether this box has valid WGS84 coordinates and non-inverted bounds.
     */
    public def isValid():Boolean {
        return this.minLat >= GeoPoint.MIN_LAT && this.maxLat <= GeoPoint.MAX_LAT
            && this.minLon >= GeoPoint.MIN_LON && this.maxLon <= GeoPoint.MAX_LON
            && this.minLat <= this.maxLat && this.minLon <= this.maxLon;
    }

    // -----------------------------------------------------------------------
    // String Representation
    // -----------------------------------------------------------------------

    public def toString():String {
        return "BoundingBox[(" + this.minLat + ", " + this.minLon
             + ") to (" + this.maxLat + ", " + this.maxLon + ")]";
    }

    public def equals(other:BoundingBox):Boolean {
        return this.minLat == other.minLat && this.minLon == other.minLon
            && this.maxLat == other.maxLat && this.maxLon == other.maxLon;
    }

    public def hashCode():Int {
        var h:Long = Double.doubleToLongBits(this.minLat);
        h = h * 31 + Double.doubleToLongBits(this.minLon);
        h = h * 31 + Double.doubleToLongBits(this.maxLat);
        h = h * 31 + Double.doubleToLongBits(this.maxLon);
        return (h ^ (h >> 32)) as Int;
    }
}
