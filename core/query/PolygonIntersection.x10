/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.query.PolygonIntersection
 *
 * Geometric polygon predicates, ray-casting point-in-polygon tests,
 * winding numbers, and shoelace area computations in X10.
 */

package convect.core.query;

import convect.core.types.GeoPoint;
import convect.core.types.BoundingBox;

public class PolygonIntersection {

    public val vertices: Rail[GeoPoint];
    public val bbox: BoundingBox;

    public def this(vertices: Rail[GeoPoint]) {
        this.vertices = vertices;
        this.bbox = computeBoundingBox(vertices);
    }

    /**
     * Compute tight axis-aligned bounding box enclosing all polygon vertices.
     */
    private static def computeBoundingBox(verts: Rail[GeoPoint]): BoundingBox {
        if (verts.size == 0) {
            return new BoundingBox(0.0, 0.0, 0.0, 0.0);
        }
        var minLat: Double = verts(0).lat;
        var maxLat: Double = verts(0).lat;
        var minLon: Double = verts(0).lon;
        var maxLon: Double = verts(0).lon;

        for (i in 1..(verts.size - 1)) {
            val p = verts(i);
            if (p.lat < minLat) minLat = p.lat;
            if (p.lat > maxLat) maxLat = p.lat;
            if (p.lon < minLon) minLon = p.lon;
            if (p.lon > maxLon) maxLon = p.lon;
        }
        return new BoundingBox(minLat, minLon, maxLat, maxLon);
    }

    /**
     * Ray-casting Jordan curve point-in-polygon test.
     * Fires a horizontal ray to the right and counts edge crossings.
     */
    public def containsPoint(pt: GeoPoint): Boolean {
        // Fast bbox rejection test
        if (!bbox.contains(pt)) {
            return false;
        }

        val n = vertices.size;
        var inside: Boolean = false;
        var j: Long = n - 1;

        for (i in 0..(n - 1)) {
            val pi = vertices(i);
            val pj = vertices(j);

            val latCond = ((pi.lat > pt.lat) != (pj.lat > pt.lat));
            if (latCond) {
                val intersectLon = (pj.lon - pi.lon) * (pt.lat - pi.lat) / (pj.lat - pi.lat) + pi.lon;
                if (pt.lon < intersectLon) {
                    inside = !inside;
                }
            }
            j = i;
        }
        return inside;
    }

    /**
     * Compute winding number for point relative to polygon.
     * Non-zero indicates the point is enclosed by the polygon boundary.
     */
    public def windingNumber(pt: GeoPoint): Long {
        if (!bbox.contains(pt)) {
            return 0;
        }

        var wn: Long = 0;
        val n = vertices.size;
        for (i in 0..(n - 1)) {
            val nextIdx = (i + 1) % n;
            val p0 = vertices(i);
            val p1 = vertices(nextIdx);

            if (p0.lat <= pt.lat) {
                if (p1.lat > pt.lat) {
                    // Upward crossing
                    val isLeft = (p1.lon - p0.lon) * (pt.lat - p0.lat) - (pt.lon - p0.lon) * (p1.lat - p0.lat);
                    if (isLeft > 0.0) {
                        wn++;
                    }
                }
            } else {
                if (p1.lat <= pt.lat) {
                    // Downward crossing
                    val isLeft = (p1.lon - p0.lon) * (pt.lat - p0.lat) - (pt.lon - p0.lon) * (p1.lat - p0.lat);
                    if (isLeft < 0.0) {
                        wn--;
                    }
                }
            }
        }
        return wn;
    }

    /**
     * Compute planar polygon area using Gauss's shoelace formula.
     */
    public def area(): Double {
        val n = vertices.size;
        if (n < 3) {
            return 0.0;
        }
        var sum: Double = 0.0;
        for (i in 0..(n - 1)) {
            val nextIdx = (i + 1) % n;
            sum += vertices(i).lon * vertices(nextIdx).lat - vertices(nextIdx).lon * vertices(i).lat;
        }
        return Math.abs(sum) * 0.5;
    }
}
