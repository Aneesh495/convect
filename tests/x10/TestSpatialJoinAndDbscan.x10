/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Test Suite: tests.x10.TestSpatialJoinAndDbscan
 *
 * Verifies Jordan ray-casting polygon intersection, spatial plane-sweep joins,
 * and DBSCAN spatial cluster expansion in X10.
 */

package convect.tests.x10;

import convect.core.types.GeoPoint;
import convect.core.types.BoundingBox;
import convect.core.types.SensorReading;
import convect.core.query.PolygonIntersection;
import convect.core.query.SpatialJoinExecutor;
import convect.core.compute.SpatialDbscan;

public class TestSpatialJoinAndDbscan {

    private static def assertCondition(cond: Boolean, msg: String): Void {
        if (!cond) {
            Console.OUT.println("FAILURE: " + msg);
            throw new Exception("Assertion failed: " + msg);
        }
    }

    public static def testPolygonPredicates(): Void {
        // Create square polygon around Downtown SF
        val verts = new Rail[GeoPoint](4);
        verts(0) = new GeoPoint(37.75, -122.45);
        verts(1) = new GeoPoint(37.75, -122.40);
        verts(2) = new GeoPoint(37.80, -122.40);
        verts(3) = new GeoPoint(37.80, -122.45);

        val poly = new PolygonIntersection(verts);

        // Point inside
        val pInside = new GeoPoint(37.77, -122.42);
        assertCondition(poly.containsPoint(pInside), "Contains inside point");
        assertCondition(poly.windingNumber(pInside) != 0, "Non-zero winding number inside");

        // Point outside
        val pOutside = new GeoPoint(37.70, -122.50);
        assertCondition(!poly.containsPoint(pOutside), "Rejects outside point");
        assertCondition(poly.windingNumber(pOutside) == 0, "Zero winding number outside");

        // Shoelace area > 0
        assertCondition(poly.area() > 0.0, "Shoelace area positive");

        Console.OUT.println("PASS: PolygonIntersection tests");
    }

    public static def testSpatialJoin(): Void {
        val verts = new Rail[GeoPoint](4);
        verts(0) = new GeoPoint(37.75, -122.45);
        verts(1) = new GeoPoint(37.75, -122.40);
        verts(2) = new GeoPoint(37.80, -122.40);
        verts(3) = new GeoPoint(37.80, -122.45);

        val polys = new Rail[PolygonIntersection](1);
        polys(0) = new PolygonIntersection(verts);

        val readings = new Rail[SensorReading](3);
        readings(0) = new SensorReading("s_inside", new GeoPoint(37.77, -122.42), 10.0, 1000L);
        readings(1) = new SensorReading("s_outside", new GeoPoint(37.60, -122.30), 20.0, 1000L);
        readings(2) = new SensorReading("s_also_inside", new GeoPoint(37.78, -122.43), 30.0, 1000L);

        val matches = SpatialJoinExecutor.executeJoin(readings, polys);
        assertCondition(matches.size == 2, "Spatial join matched exactly 2 interior sensors");

        Console.OUT.println("PASS: SpatialJoinExecutor tests");
    }

    public static def testDbscanClustering(): Void {
        val readings = new Rail[SensorReading](6);
        // Cluster 1 (tight cluster near 37.77, -122.42)
        readings(0) = new SensorReading("c1_0", new GeoPoint(37.770, -122.420), 1.0, 1000L);
        readings(1) = new SensorReading("c1_1", new GeoPoint(37.771, -122.421), 1.0, 1000L);
        readings(2) = new SensorReading("c1_2", new GeoPoint(37.772, -122.420), 1.0, 1000L);

        // Cluster 2 (tight cluster near 37.85, -122.30)
        readings(3) = new SensorReading("c2_0", new GeoPoint(37.850, -122.300), 2.0, 1000L);
        readings(4) = new SensorReading("c2_1", new GeoPoint(37.851, -122.301), 2.0, 1000L);

        // Outlier far away
        readings(5) = new SensorReading("noise_0", new GeoPoint(38.500, -120.000), 9.0, 1000L);

        // eps = 500 meters, minPts = 2
        val dbscan = new SpatialDbscan(500.0, 2);
        val labels = dbscan.cluster(readings);

        assertCondition(labels(0) == labels(1) && labels(1) == labels(2), "Cluster 1 points share label");
        assertCondition(labels(3) == labels(4), "Cluster 2 points share label");
        assertCondition(labels(0) != labels(3), "Cluster 1 and Cluster 2 distinct");
        assertCondition(labels(5) == SpatialDbscan.NOISE, "Isolated point classified as noise");

        Console.OUT.println("PASS: SpatialDbscan tests");
    }

    public static def main(args: Rail[String]): Void {
        Console.OUT.println("Running TestSpatialJoinAndDbscan...");
        testPolygonPredicates();
        testSpatialJoin();
        testDbscanClustering();
        Console.OUT.println("ALL Spatial Join and DBSCAN tests passed successfully!");
    }
}
