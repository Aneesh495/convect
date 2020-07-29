package convect.core.fault;

/**
 * HeartbeatMonitor detects peer Place network partitions and hardware failures.
 *
 * Implements a threshold failure detector tracking inter-heartbeat arrival times.
 * If a Place fails to emit a heartbeat within heartbeatTimeoutMs, it is flagged
 * as suspected to initiate failover tile reassignment.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class HeartbeatMonitor {

    public val numPlaces:Long;
    public val heartbeatTimeoutMs:Long;
    public val lastHeartbeatWallTime:Rail[Long];
    public val placeHealthy:Rail[Boolean];

    public def this(numPlaces:Long, heartbeatTimeoutMs:Long) {
        this.numPlaces = numPlaces;
        this.heartbeatTimeoutMs = heartbeatTimeoutMs;
        val now = System.currentTimeMillis();
        this.lastHeartbeatWallTime = new Rail[Long](numPlaces, (i:Long) => now);
        this.placeHealthy = new Rail[Boolean](numPlaces, (i:Long) => true);
    }

    /**
     * Record an incoming heartbeat from placeId.
     */
    public def recordHeartbeat(placeId:Long):void {
        if (placeId >= 0L && placeId < this.numPlaces) {
            this.lastHeartbeatWallTime(placeId) = System.currentTimeMillis();
            this.placeHealthy(placeId) = true;
        }
    }

    /**
     * Poll all places and return placeId of any detected failed place, or -1 if all healthy.
     */
    public def detectFailure():Long {
        val now = System.currentTimeMillis();
        for (p in 0..(this.numPlaces - 1L)) {
            if (this.placeHealthy(p)) {
                val elapsed = now - this.lastHeartbeatWallTime(p);
                if (elapsed > this.heartbeatTimeoutMs) {
                    this.placeHealthy(p) = false;
                    return p;
                }
            }
        }
        return -1L;
    }
}
