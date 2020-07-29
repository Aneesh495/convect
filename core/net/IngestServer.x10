package convect.core.net;

import convect.core.types.SensorReading;
import convect.core.topology.TileRouter;

/**
 * IngestServer manages network endpoints accepting binary sensor observation streams.
 *
 * Deserializes frames, computes destination Place IDs via TileRouter, and dispatches
 * records to target Place workers using asynchronous activities.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class IngestServer {

    public val port:Int;
    public val router:TileRouter;
    public var running:Boolean;
    public var totalMessagesReceived:Long;
    public var totalBytesReceived:Long;

    public def this(port:Int, router:TileRouter) {
        this.port = port;
        this.router = router;
        this.running = false;
        this.totalMessagesReceived = 0L;
        this.totalBytesReceived = 0L;
    }

    public def start():void {
        this.running = true;
    }

    public def stop():void {
        this.running = false;
    }

    /**
     * Dispatch an ingested reading to its owning Place.
     */
    public def dispatchReading(reading:SensorReading):Long {
        this.totalMessagesReceived++;
        /* Route reading to target place partition */
        val targetPlaceId = this.router.routeHilbertIndex(reading.sensorId);
        return targetPlaceId;
    }

    public def toString():String {
        return "IngestServer(port=" + this.port + ", running=" + this.running +
               ", msgs=" + this.totalMessagesReceived + ")";
    }
}
