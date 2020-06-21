package convect.core.clock;

import convect.core.types.SensorReading;
import x10.util.ArrayList;

/**
 * SlidingTimeWindow incrementally maintains running statistical aggregations
 * across a fixed temporal span [now - duration, now], sliding forward by slideStep.
 *
 * Employs Welford's numerically stable single-pass variance algorithm to avoid
 * catastrophic floating-point cancellation on large sensor sums.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class SlidingTimeWindow {

    public val durationMs:Long;
    public val slideStepMs:Long;
    public var windowStart:Long;
    public var windowEnd:Long;

    public var count:Long;
    public var sum:Double;
    public var minVal:Double;
    public var maxVal:Double;
    public var m2:Double; /* Welford sum of squared differences */

    public def this(durationMs:Long, slideStepMs:Long, initialTime:Long) {
        this.durationMs = durationMs;
        this.slideStepMs = slideStepMs;
        this.windowStart = initialTime;
        this.windowEnd = initialTime + durationMs;
        this.reset();
    }

    public def reset():void {
        this.count = 0L;
        this.sum = 0.0;
        this.minVal = Double.MAX_VALUE;
        this.maxVal = -Double.MAX_VALUE;
        this.m2 = 0.0;
    }

    /**
     * Add an observation into the active window.
     */
    public def addReading(val:Double):void {
        this.count++;
        this.sum += val;
        if (val < this.minVal) this.minVal = val;
        if (val > this.maxVal) this.maxVal = val;

        /* Welford update */
        val delta = val - (this.sum / (this.count as Double));
        val delta2 = val - ((this.sum + val) / ((this.count + 1L) as Double));
        this.m2 += delta * delta2;
    }

    public def mean():Double {
        return if (this.count > 0L) (this.sum / (this.count as Double)) else 0.0;
    }

    public def variance():Double {
        return if (this.count > 1L) (this.m2 / ((this.count - 1L) as Double)) else 0.0;
    }

    public def stddev():Double {
        return Math.sqrt(variance());
    }

    /**
     * Advance window by slide step.
     */
    public def slide():void {
        this.windowStart += this.slideStepMs;
        this.windowEnd += this.slideStepMs;
        this.reset();
    }
}
