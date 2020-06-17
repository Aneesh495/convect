package convect.core.clock;

/**
 * EventWatermark tracks progress of event time across distributed Place partitions.
 *
 * Implements low-watermark semantics for handling out-of-order sensor transmissions.
 * When sensors experience wireless transmission jitter or batch buffers, observations
 * may arrive delayed. The watermark guarantees that no further events with timestamp
 * earlier than (currentWatermark - maxLatenessMs) will be incorporated into finalized windows.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class EventWatermark {

    public var currentWatermark:Long;
    public val maxLatenessMs:Long;
    public var lastAdvanceWallTime:Long;
    public var lateEventsDropped:Long;

    public def this(maxLatenessMs:Long) {
        this.currentWatermark = 0L;
        this.maxLatenessMs = maxLatenessMs;
        this.lastAdvanceWallTime = System.currentTimeMillis();
        this.lateEventsDropped = 0L;
    }

    /**
     * Ingest an observation timestamp and potentially advance the watermark.
     */
    public def observe(timestamp:Long):Boolean {
        /* Check if event is too late to process */
        if (this.currentWatermark > 0L && timestamp < (this.currentWatermark - this.maxLatenessMs)) {
            this.lateEventsDropped++;
            return false;
        }

        /* Monotonically advance watermark */
        val proposed = timestamp - this.maxLatenessMs;
        if (proposed > this.currentWatermark) {
            this.currentWatermark = proposed;
            this.lastAdvanceWallTime = System.currentTimeMillis();
        }

        return true;
    }

    /**
     * Check if a temporal window ending at windowEnd can be safely finalized.
     */
    public def isWindowComplete(windowEnd:Long):Boolean {
        return this.currentWatermark >= windowEnd;
    }

    public def toString():String {
        return "EventWatermark(watermark=" + this.currentWatermark +
               ", maxLateness=" + this.maxLatenessMs + "ms, lateDropped=" +
               this.lateEventsDropped + ")";
    }
}
