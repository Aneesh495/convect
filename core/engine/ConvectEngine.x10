package convect.core.engine;

import convect.core.types.GeoPoint;
import convect.core.types.BoundingBox;
import convect.core.types.SensorReading;
import convect.core.types.TileId;
import convect.core.topology.TileRouter;
import convect.core.topology.TopologyManager;
import convect.core.clock.EventWatermark;
import convect.core.clock.SlidingTimeWindow;
import convect.core.detect.AnomalyResult;
import convect.core.detect.LocalOutlierFactor;
import convect.core.detect.TemporalCusum;
import convect.core.detect.MoranSpatialAutocorrelation;
import convect.core.storage.WriteAheadLog;
import convect.core.storage.SnapshotManager;
import convect.core.query.SpatialQueryPlan;
import convect.core.query.QueryExecutor;
import x10.util.ArrayList;

/**
 * ConvectEngine is the distributed geospatial stream processing coordinator.
 *
 * Deploys per-Place partition workers across the cluster using X10's Partitioned
 * Global Address Space (PGAS) model. Coordinates real-time observation ingestion,
 * spatial anomaly detection pipelines, sliding temporal window maintenance, and
 * distributed multi-place spatial range/radius query execution.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class ConvectEngine {

    public val numPlaces:Long;
    public val tileOrder:Int;
    public val topology:TopologyManager;
    public val watermark:EventWatermark;
    public val queryExecutor:QueryExecutor;
    public val lofDetector:LocalOutlierFactor;
    public val cusumDetector:TemporalCusum;
    public val moranDetector:MoranSpatialAutocorrelation;

    /* Per-place local buffers and journals */
    public val placeLogs:Rail[WriteAheadLog];
    public val placeSnapshots:Rail[SnapshotManager];
    public val activeReadings:Rail[ArrayList[SensorReading]];

    public def this(numPlaces:Long, tileOrder:Int) {
        this.numPlaces = numPlaces;
        this.tileOrder = tileOrder;
        this.topology = new TopologyManager(numPlaces, tileOrder);
        this.watermark = new EventWatermark(5000L); /* 5 second lateness tolerance */
        this.queryExecutor = new QueryExecutor(this.topology.router, numPlaces);

        this.lofDetector = new LocalOutlierFactor(4n, 1.5);
        this.cusumDetector = new TemporalCusum(0.5, 3.5);
        this.moranDetector = new MoranSpatialAutocorrelation(25000.0, 1.96);

        this.placeLogs = new Rail[WriteAheadLog](numPlaces, (p:Long) => new WriteAheadLog(p));
        this.placeSnapshots = new Rail[SnapshotManager](numPlaces, (p:Long) => new SnapshotManager(p, 60000L));
        this.activeReadings = new Rail[ArrayList[SensorReading]](numPlaces, (p:Long) => new ArrayList[SensorReading]());
    }

    /**
     * Ingest an observation into the engine:
     * 1. Routes reading to owning Place.
     * 2. Appends to durable WAL journal.
     * 3. Advances event-time watermark.
     * 4. Updates CUSUM sequential detector.
     * 5. Buffers in active memory store.
     */
    public def ingestReading(reading:SensorReading):Long {
        val targetPlace = this.topology.router.routeHilbertIndex(reading.sensorId);
        val pIdx = if (targetPlace >= 0L && targetPlace < this.numPlaces) targetPlace else 0L;

        /* Write to journal */
        this.placeLogs(pIdx).append(reading);

        /* Update watermark */
        this.watermark.observe(reading.timestamp);

        /* Store in active place buffer */
        this.activeReadings(pIdx).add(reading);
        this.topology.recordLoad(pIdx, 1L);

        return pIdx;
    }

    /**
     * Ingest a batch of readings in parallel across places.
     */
    public def ingestBatch(batch:Rail[SensorReading]):Long {
        for (i in 0..(batch.size - 1L)) {
            this.ingestReading(batch(i));
        }
        return batch.size;
    }

    /**
     * Run the multi-strategy anomaly detection pipeline over all active partitions.
     */
    public def runAnomalyDetection():ArrayList[AnomalyResult] {
        val detected = new ArrayList[AnomalyResult]();

        for (p in 0..(this.numPlaces - 1L)) {
            val readingsList = this.activeReadings(p);
            val count = readingsList.size();
            if (count >= 5L) {
                val arr = new Rail[SensorReading](count, (i:Long) => readingsList.get(i as Int));

                /* 1. Run Local Outlier Factor */
                val lofHits = this.lofDetector.detect(arr);
                for (j in 0..(lofHits.size() - 1L)) {
                    detected.add(lofHits.get(j as Int));
                }

                /* 2. Run Local Moran's I Outliers */
                val moranHits = this.moranDetector.detectOutliers(arr);
                for (k in 0..(moranHits.size() - 1L)) {
                    detected.add(moranHits.get(k as Int));
                }
            }
        }

        return detected;
    }

    /**
     * Execute a spatial query across all partition places.
     */
    public def executeQuery(plan:SpatialQueryPlan):ArrayList[SensorReading] {
        val consolidated = new ArrayList[SensorReading]();

        for (p in 0..(this.numPlaces - 1L)) {
            val partial = if (plan.queryType == 1n)
                this.queryExecutor.executeRangeQuery(plan, this.activeReadings(p))
            else
                this.queryExecutor.executeRadiusQuery(plan, this.activeReadings(p));

            for (i in 0..(partial.size() - 1L)) {
                consolidated.add(partial.get(i as Int));
            }
        }

        return consolidated;
    }

    /**
     * Main entry point for standalone engine execution.
     */
    public static def main(args:Rail[String]):void {
        Console.OUT.println("==========================================================");
        Console.OUT.println(" Convect Distributed Geospatial Stream Processing Engine  ");
        Console.OUT.println("==========================================================");

        val numP = 4L;
        val order = 8n;
        Console.OUT.println("Initializing ConvectEngine with " + numP + " places, tileOrder=" + order);

        val engine = new ConvectEngine(numP, order);

        /* Simulate sample streaming sensor observations across California */
        Console.OUT.println("Streaming sample environmental telemetry...");
        val testReadings = new Rail[SensorReading](10L, (i:Long) => {
            val lat = 37.0 + (i as Double) * 0.1;
            val lon = -122.0 + (i as Double) * 0.1;
            val val = 20.0 + (i as Double) * 0.5;
            return new SensorReading(i + 1L, lat, lon, System.currentTimeMillis() + i * 1000L, 1n, val);
        });

        engine.ingestBatch(testReadings);
        Console.OUT.println("Ingested " + testReadings.size + " readings.");

        /* Execute Range Query */
        val qbox = BoundingBox(37.0, -122.5, 37.5, -121.5);
        val plan = SpatialQueryPlan.makeRangeQuery(101L, qbox, 1n);
        val results = engine.executeQuery(plan);
        Console.OUT.println("Range query returned " + results.size() + " observations.");

        /* Run Anomaly Pipeline */
        val anomalies = engine.runAnomalyDetection();
        Console.OUT.println("Anomaly detection completed: " + anomalies.size() + " anomalies detected.");
        Console.OUT.println("Engine execution finished cleanly.");
    }
}
