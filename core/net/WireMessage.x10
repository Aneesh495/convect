package convect.core.net;

import convect.core.types.SensorReading;

/**
 * WireMessage models framed network messages received over the binary ingestion socket.
 *
 * Types:
 *   1 = SENSOR_READING
 *   2 = BATCH_READINGS
 *   3 = HEARTBEAT
 *   4 = CONTROL
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public struct WireMessage {

    public val msgType:Int;
    public val sequenceNumber:Long;
    public val payloadSize:Int;

    public def this(msgType:Int, sequenceNumber:Long, payloadSize:Int) {
        this.msgType = msgType;
        this.sequenceNumber = sequenceNumber;
        this.payloadSize = payloadSize;
    }

    public def isReading():Boolean {
        return this.msgType == 1n || this.msgType == 2n;
    }

    public def isHeartbeat():Boolean {
        return this.msgType == 3n;
    }

    public def isControl():Boolean {
        return this.msgType == 4n;
    }

    public def toString():String {
        return "WireMessage(type=" + this.msgType + ", seq=" + this.sequenceNumber +
               ", bytes=" + this.payloadSize + ")";
    }
}
