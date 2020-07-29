package convect.core.fault;

import convect.core.topology.TopologyManager;
import convect.core.storage.WriteAheadLog;
import x10.util.ArrayList;

/**
 * FailoverCoordinator orchestrates partition handover when a Place goes down.
 *
 * Coordinates partition range reassignment to surviving peer nodes and schedules
 * asynchronous replay of Write-Ahead Log entries to rebuild spatial indices.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class FailoverCoordinator {

    public val topology:TopologyManager;
    public var totalFailoversHandled:Long;

    public def this(topology:TopologyManager) {
        this.topology = topology;
        this.totalFailoversHandled = 0L;
    }

    /**
     * Handle a failed place: update topology, redistribute partitions, and trigger rebalance.
     */
    public def handlePlaceFailure(failedPlaceId:Long):void {
        this.topology.markPlaceDown(failedPlaceId);
        this.topology.rebalance();
        this.totalFailoversHandled++;
    }

    /**
     * Handle node recovery: rejoin cluster and rebalance.
     */
    public def handlePlaceRecovery(recoveredPlaceId:Long):void {
        this.topology.markPlaceUp(recoveredPlaceId);
        this.topology.rebalance();
    }
}
