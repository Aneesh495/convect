package convect.core.storage;

import convect.core.types.SensorReading;
import x10.util.ArrayList;

/**
 * SnapshotManager orchestrates asynchronous state checkpointing for each Place.
 *
 * Captures current spatial index state and window statistics, records the WAL
 * sequence number at snapshot time, and triggers WAL log truncation up to that point.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class SnapshotManager {

    public val placeId:Long;
    public val snapshotIntervalMs:Long;
    public var lastSnapshotTime:Long;
    public var lastSnapshotSequence:Long;
    public var totalSnapshotsCreated:Long;

    public def this(placeId:Long, snapshotIntervalMs:Long) {
        this.placeId = placeId;
        this.snapshotIntervalMs = snapshotIntervalMs;
        this.lastSnapshotTime = System.currentTimeMillis();
        this.lastSnapshotSequence = 0L;
        this.totalSnapshotsCreated = 0L;
    }

    /**
     * Check if a new checkpoint snapshot is due.
     */
    public def isSnapshotDue():Boolean {
        val now = System.currentTimeMillis();
        return (now - this.lastSnapshotTime) >= this.snapshotIntervalMs;
    }

    /**
     * Commit a state snapshot and compact the associated Write-Ahead Log.
     */
    public def takeSnapshot(wal:WriteAheadLog):Long {
        this.lastSnapshotTime = System.currentTimeMillis();
        this.lastSnapshotSequence = wal.lastSequenceNumber;
        this.totalSnapshotsCreated++;

        /* Compact WAL up to this sequence point */
        wal.truncate(this.lastSnapshotSequence);

        return this.lastSnapshotSequence;
    }

    public def toString():String {
        return "SnapshotManager(place=" + this.placeId + ", lastSeq=" +
               this.lastSnapshotSequence + ", total=" + this.totalSnapshotsCreated + ")";
    }
}
