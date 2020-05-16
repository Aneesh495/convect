package convect.core.types;

/**
 * GeoPoint represents a geographic coordinate on Earth's surface.
 *
 * This is a value type (struct) because geographic coordinates are immutable
 * and frequently copied between places during spatial operations. Using a
 * struct avoids heap allocation overhead for what is essentially just two
 * floating-point numbers.
 *
 * Coordinates use the WGS84 datum (the standard for GPS and most mapping):
 *   - Latitude ranges from -90.0 (South Pole) to +90.0 (North Pole)
 *   - Longitude ranges from -180.0 (west) to +180.0 (east)
 *
 * The struct provides great-circle distance via the Haversine formula,
 * which is accurate for most practical distances. For sub-meter precision
 * at long ranges, consider Vincenty's formulae (not implemented here
 * because sensor-level accuracy rarely demands it).
 */
public struct GeoPoint {

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    /** Mean radius of Earth in meters (WGS84 volumetric mean). */
    public static val EARTH_RADIUS_M:Double = 6371008.8;

    /** Conversion factor from degrees to radians. */
    private static val DEG_TO_RAD:Double = Math.PI / 180.0;

    /** Minimum valid latitude (South Pole). */
    public static val MIN_LAT:Double = -90.0;

    /** Maximum valid latitude (North Pole). */
    public static val MAX_LAT:Double = 90.0;

    /** Minimum valid longitude (antimeridian, west side). */
    public static val MIN_LON:Double = -180.0;

    /** Maximum valid longitude (antimeridian, east side). */
    public static val MAX_LON:Double = 180.0;

    // -----------------------------------------------------------------------
    // Fields
    // -----------------------------------------------------------------------

    /** Latitude in decimal degrees, WGS84. */
    public val lat:Double;

    /** Longitude in decimal degrees, WGS84. */
    public val lon:Double;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    /**
     * Create a new geographic point.
     *
     * @param lat Latitude in decimal degrees [-90, +90]
     * @param lon Longitude in decimal degrees [-180, +180]
     */
    public def this(lat:Double, lon:Double) {
        this.lat = lat;
        this.lon = lon;
    }

    // -----------------------------------------------------------------------
    // Distance Calculations
    // -----------------------------------------------------------------------

    /**
     * Compute the great-circle distance to another point using the Haversine
     * formula. This gives the shortest distance over Earth's surface between
     * two points, ignoring elevation differences.
     *
     * Accuracy: sub-meter for distances up to several thousand kilometers.
     * Performance: involves 2 sqrt calls and 4 trig calls, which is fine
     * for per-reading computations but should be avoided in tight inner
     * loops over millions of pairs (use squared Euclidean approximation
     * for initial filtering instead).
     *
     * @param other The target point
     * @return Distance in meters
     */
    public def distanceTo(other:GeoPoint):Double {
        val dLat = (other.lat - this.lat) * DEG_TO_RAD;
        val dLon = (other.lon - this.lon) * DEG_TO_RAD;
        val lat1Rad = this.lat * DEG_TO_RAD;
        val lat2Rad = other.lat * DEG_TO_RAD;

        // Haversine formula: a = sin^2(dLat/2) + cos(lat1) * cos(lat2) * sin^2(dLon/2)
        val sinHalfDLat = Math.sin(dLat / 2.0);
        val sinHalfDLon = Math.sin(dLon / 2.0);
        val a = sinHalfDLat * sinHalfDLat
              + Math.cos(lat1Rad) * Math.cos(lat2Rad)
              * sinHalfDLon * sinHalfDLon;

        // c = 2 * atan2(sqrt(a), sqrt(1-a))
        val c = 2.0 * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a));

        return EARTH_RADIUS_M * c;
    }

    /**
     * Compute a fast approximate squared distance for spatial filtering.
     *
     * This treats lat/lon as Cartesian coordinates and returns the squared
     * Euclidean distance in "degree-squared" units. It is NOT a true distance
     * metric (degrees of longitude vary with latitude), but it preserves
     * ordering for nearby points at the same latitude band, which makes it
     * useful as a cheap first-pass filter before computing Haversine.
     *
     * @param other The target point
     * @return Approximate squared distance in degree-squared units
     */
    public def approxDistanceSquared(other:GeoPoint):Double {
        val dLat = other.lat - this.lat;
        val dLon = other.lon - this.lon;
        return dLat * dLat + dLon * dLon;
    }

    /**
     * Compute the initial bearing (forward azimuth) from this point to
     * another, measured clockwise from true north.
     *
     * @param other The target point
     * @return Bearing in degrees [0, 360)
     */
    public def bearingTo(other:GeoPoint):Double {
        val lat1 = this.lat * DEG_TO_RAD;
        val lat2 = other.lat * DEG_TO_RAD;
        val dLon = (other.lon - this.lon) * DEG_TO_RAD;

        val y = Math.sin(dLon) * Math.cos(lat2);
        val x = Math.cos(lat1) * Math.sin(lat2)
              - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);

        val bearing = Math.atan2(y, x) * (180.0 / Math.PI);
        // Normalize to [0, 360)
        return (bearing + 360.0) % 360.0;
    }

    /**
     * Compute a destination point given an initial bearing and distance.
     * Uses the direct geodesic problem solution on a sphere.
     *
     * @param bearingDeg Initial bearing in degrees from north
     * @param distanceM Distance in meters
     * @return The destination point
     */
    public def destinationPoint(bearingDeg:Double, distanceM:Double):GeoPoint {
        val angularDist = distanceM / EARTH_RADIUS_M;
        val bearingRad = bearingDeg * DEG_TO_RAD;
        val lat1 = this.lat * DEG_TO_RAD;
        val lon1 = this.lon * DEG_TO_RAD;

        val sinLat1 = Math.sin(lat1);
        val cosLat1 = Math.cos(lat1);
        val sinAngDist = Math.sin(angularDist);
        val cosAngDist = Math.cos(angularDist);

        val lat2 = Math.asin(
            sinLat1 * cosAngDist + cosLat1 * sinAngDist * Math.cos(bearingRad)
        );
        val lon2 = lon1 + Math.atan2(
            Math.sin(bearingRad) * sinAngDist * cosLat1,
            cosAngDist - sinLat1 * Math.sin(lat2)
        );

        return GeoPoint(lat2 * (180.0 / Math.PI), lon2 * (180.0 / Math.PI));
    }

    // -----------------------------------------------------------------------
    // Validation
    // -----------------------------------------------------------------------

    /**
     * Check whether this point has valid WGS84 coordinates.
     *
     * @return true if lat is in [-90, 90] and lon is in [-180, 180]
     */
    public def isValid():Boolean {
        return this.lat >= MIN_LAT && this.lat <= MAX_LAT
            && this.lon >= MIN_LON && this.lon <= MAX_LON;
    }

    /**
     * Check whether this point falls within the given bounding box.
     *
     * @param bbox The bounding box to test against
     * @return true if this point is inside (inclusive of boundaries)
     */
    public def isWithin(bbox:BoundingBox):Boolean {
        return this.lat >= bbox.minLat && this.lat <= bbox.maxLat
            && this.lon >= bbox.minLon && this.lon <= bbox.maxLon;
    }

    // -----------------------------------------------------------------------
    // Midpoint
    // -----------------------------------------------------------------------

    /**
     * Compute the geographic midpoint between this point and another.
     * Uses the spherical midpoint formula for accuracy at large distances.
     *
     * @param other The other point
     * @return The midpoint on the great circle connecting the two points
     */
    public def midpointTo(other:GeoPoint):GeoPoint {
        val lat1 = this.lat * DEG_TO_RAD;
        val lon1 = this.lon * DEG_TO_RAD;
        val lat2 = other.lat * DEG_TO_RAD;
        val dLon = (other.lon - this.lon) * DEG_TO_RAD;

        val bx = Math.cos(lat2) * Math.cos(dLon);
        val by = Math.cos(lat2) * Math.sin(dLon);

        val lat3 = Math.atan2(
            Math.sin(lat1) + Math.sin(lat2),
            Math.sqrt((Math.cos(lat1) + bx) * (Math.cos(lat1) + bx) + by * by)
        );
        val lon3 = lon1 + Math.atan2(by, Math.cos(lat1) + bx);

        return GeoPoint(lat3 * (180.0 / Math.PI), lon3 * (180.0 / Math.PI));
    }

    // -----------------------------------------------------------------------
    // String Representation
    // -----------------------------------------------------------------------

    /**
     * Human-readable string representation of this point.
     *
     * @return String in format "GeoPoint(lat, lon)"
     */
    public def toString():String {
        return "GeoPoint(" + this.lat + ", " + this.lon + ")";
    }

    /**
     * Compact coordinate string suitable for logging.
     *
     * @return String in format "(lat, lon)"
     */
    public def toCoordString():String {
        return "(" + this.lat + ", " + this.lon + ")";
    }

    // -----------------------------------------------------------------------
    // Equality
    // -----------------------------------------------------------------------

    /**
     * Exact equality check. For floating-point comparison with tolerance,
     * use approxEquals() instead.
     */
    public def equals(other:GeoPoint):Boolean {
        return this.lat == other.lat && this.lon == other.lon;
    }

    /**
     * Approximate equality within a tolerance in degrees.
     *
     * @param other The point to compare with
     * @param epsilonDeg Maximum allowed difference in degrees
     * @return true if both lat and lon differ by less than epsilon
     */
    public def approxEquals(other:GeoPoint, epsilonDeg:Double):Boolean {
        return Math.abs(this.lat - other.lat) < epsilonDeg
            && Math.abs(this.lon - other.lon) < epsilonDeg;
    }

    /**
     * Hash code for use in hash-based collections.
     */
    public def hashCode():Int {
        // Combine the bit patterns of lat and lon using a mixing function.
        // This is a simple but effective approach for spatial data.
        val latBits = Double.doubleToLongBits(this.lat);
        val lonBits = Double.doubleToLongBits(this.lon);
        val combined = latBits * 31n + lonBits;
        return (combined ^ (combined >> 32)) as Int;
    }
}
