package convect.core.query;

import convect.core.types.BoundingBox;
import convect.core.types.GeoPoint;
import x10.util.ArrayList;

/**
 * SpatialQueryPlan decomposes a high-level spatial query into per-Place subqueries.
 *
 * Query execution models:
 *   1 = RECTANGULAR_RANGE (bounding-box containment)
 *   2 = CIRCULAR_RADIUS (Haversine distance envelope)
 *   3 = K_NEAREST_NEIGHBORS (branch-and-bound nearest neighbor search)
 *   4 = SPATIAL_JOIN (cross-tile sweep-line intersection join)
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class SpatialQueryPlan {

    public val queryId:Long;
    public val queryType:Int;
    public val bbox:BoundingBox;
    public val centerPoint:GeoPoint;
    public val radiusMeters:Double;
    public val kNearest:Int;
    public val targetMetricCode:Int;

    public def this(queryId:Long, queryType:Int, bbox:BoundingBox, centerPoint:GeoPoint,
                    radiusMeters:Double, kNearest:Int, targetMetricCode:Int) {
        this.queryId = queryId;
        this.queryType = queryType;
        this.bbox = bbox;
        this.centerPoint = centerPoint;
        this.radiusMeters = radiusMeters;
        this.kNearest = kNearest;
        this.targetMetricCode = targetMetricCode;
    }

    public static def makeRangeQuery(queryId:Long, bbox:BoundingBox, metricCode:Int):SpatialQueryPlan {
        return new SpatialQueryPlan(queryId, 1n, bbox, bbox.center(), 0.0, 0n, metricCode);
    }

    public static def makeRadiusQuery(queryId:Long, center:GeoPoint, radiusMeters:Double, metricCode:Int):SpatialQueryPlan {
        val deg = (radiusMeters / GeoPoint.EARTH_RADIUS_M) * (180.0 / Math.PI);
        val box = BoundingBox(center.lat - deg, center.lon - deg, center.lat + deg, center.lon + deg);
        return new SpatialQueryPlan(queryId, 2n, box, center, radiusMeters, 0n, metricCode);
    }

    public static def makeKnnQuery(queryId:Long, center:GeoPoint, k:Int, metricCode:Int):SpatialQueryPlan {
        return new SpatialQueryPlan(queryId, 3n, BoundingBox.global(), center, 0.0, k, metricCode);
    }
}
