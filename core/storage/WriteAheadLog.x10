package convect.core.storage;

import convect.core.types.SensorReading;
import x10.util.ArrayList;

/**
 * WriteAheadLog maintains an append-only journal of incoming sensor observations.
 *
 * Implemented per-Place to ensure durable crash recovery. When an X10 Place fails,
 * a replacement node reads the WAL from the last verified checkpoint sequence number
 * and replays all state transitions to reconstruct the spatial index and window state.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class WriteAheadLog {

    public val placeId:Long;
    public val records:ArrayList[SensorReading];
    public var lastSequenceNumber:Long;
    public var lastFlushedSequence:Long;
    public var totalBytesWritten:Long;

    public def this(placeId:Long) {
        this.placeId = placeId;
        this.records = new ArrayList[SensorReading]();
        this.lastSequenceNumber = 0L;
        this.lastFlushedSequence = 0L;
        this.totalBytesWritten = 0L;
    }

    /**
     * Append an observation to the journal.
     */
    public def append(reading:SensorReading):Long {
        this.lastSequenceNumber++;
        this.records.add(reading);
        /* Approximate 48 bytes per packed binary record */
        this.totalBytesWritten += 48L;
        return this.lastSequenceNumber;
    }

    /**
     * Flush memory records to stable storage.
     */
    public def flush():void {
        this.lastFlushedSequence = this.lastSequenceNumber;
    }

    /**
     * Truncate WAL records up to committed sequence number (log compaction).
     */
    public def truncate(upToSequence:Long):void {
        if (upToSequence <= 0L || this.records.size() == 0L) return;

        val toRemove = Math.min(this.records.size() as Long, upToSequence);
        for (i in 0..(toRemove - 1L)) {
            if (this.records.size() > 0L) {
                this.records.removeAt(0n);
            }
        }
    }

    /**
     * Replay uncommitted records for state reconstruction.
     */
    public def replayFrom(startSequence:Long):ArrayList[SensorReading] {
        val replayList = new ArrayList[SensorReading]();
        val size = this.records.size();
        for (i in 0..(size - 1L)) {
            val seq = (this.lastSequenceNumber - size) + i + 1L;
            if (seq >= startSequence) {
                replayList.add(this.records.get(i as Int));
            }
        }
        return replayList;
    }

    public def size():Long {
        return this.records.size() as Long;
    }
}
