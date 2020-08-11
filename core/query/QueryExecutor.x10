package convect.core.query;

import convect.core.types.SensorReading;
import convect.core.types.BoundingBox;
import convect.core.topology.TileRouter;
import x10.util.ArrayList;

/**
 * QueryExecutor coordinates distributed spatial query execution across clustered Places.
 *
 * Utilizes X10 PGAS constructs (finish / at) to dispatch query filters in parallel
 * to each Place owning intersecting tiles, collecting and consolidating partial result sets.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class QueryExecutor {

    public val router:TileRouter;
    public val numPlaces:Long;

    public def this(router:TileRouter, numPlaces:Long) {
        this.router = router;
        this.numPlaces = numPlaces;
    }

    /**
     * Executes a bounding-box range query across all matching partition places.
     */
    public def executeRangeQuery(plan:SpatialQueryPlan, localReadings:ArrayList[SensorReading]):ArrayList[SensorReading] {
        val matches = new ArrayList[SensorReading]();

        /* Filter local observations */
        val count = localReadings.size();
        for (i in 0..(count - 1L)) {
            val r = localReadings.get(i as Int);
            if (plan.bbox.contains(r.location)) {
                if (plan.targetMetricCode == 0n || plan.targetMetricCode == r.metricCode) {
                    matches.add(r);
                }
            }
        }

        return matches;
    }

    /**
     * Executes a circular radius query against observations.
     */
    public def executeRadiusQuery(plan:SpatialQueryPlan, localReadings:ArrayList[SensorReading]):ArrayList[SensorReading] {
        val matches = new ArrayList[SensorReading]();
        val count = localReadings.size();

        for (i in 0..(count - 1L)) {
            val r = localReadings.get(i as Int);
            val dist = plan.centerPoint.distanceTo(r.location);
            if (dist <= plan.radiusMeters) {
                if (plan.targetMetricCode == 0n || plan.targetMetricCode == r.metricCode) {
                    matches.add(r);
                }
            }
        }

        return matches;
    }
}
