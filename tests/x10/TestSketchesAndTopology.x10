/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Test Suite: tests.x10.TestSketchesAndTopology
 *
 * Verifies HyperLogLog spatial cardinality estimation, streaming spatial
 * aggregation hulls, dynamic load rebalancing, and consensus state machines.
 */

package convect.tests.x10;

import convect.core.types.GeoPoint;
import convect.core.types.SensorReading;
import convect.core.aggregate.HyperLogLogSpatial;
import convect.core.aggregate.SpatialAggregator;
import convect.core.topology.PlacePartition;
import convect.core.topology.DynamicLoadBalancer;
import convect.core.topology.ConsensusRaftState;

public class TestSketchesAndTopology {

    private static def assertCondition(cond: Boolean, msg: String): Void {
        if (!cond) {
            Console.OUT.println("FAILURE: " + msg);
            throw new Exception("Assertion failed: " + msg);
        }
    }

    public static def testHyperLogLog(): Void {
        val hll1 = new HyperLogLogSpatial(10);
        val hll2 = new HyperLogLogSpatial(10);

        // Add 50 distinct sensor IDs to hll1
        for (i in 0..49) {
            hll1.add("sensor_alpha_" + i);
        }
        val est1 = hll1.estimate();
        assertCondition(est1 >= 40.0 && est1 <= 60.0, "HLL1 cardinality within 20% error");

        // Add 50 distinct sensor IDs to hll2
        for (i in 50..99) {
            hll2.add("sensor_beta_" + i);
        }
        val est2 = hll2.estimate();
        assertCondition(est2 >= 40.0 && est2 <= 60.0, "HLL2 cardinality within 20% error");

        // Merge hll2 into hll1 -> total ~ 100
        hll1.merge(hll2);
        val mergedEst = hll1.estimate();
        assertCondition(mergedEst >= 80.0 && mergedEst <= 120.0, "Merged HLL cardinality ~100");

        Console.OUT.println("PASS: HyperLogLogSpatial tests");
    }

    public static def testSpatialAggregator(): Void {
        val agg = new SpatialAggregator();
        agg.add(new SensorReading("s1", new GeoPoint(10.0, 20.0), 100.0, 1000L));
        agg.add(new SensorReading("s2", new GeoPoint(20.0, 40.0), 200.0, 1000L));

        assertCondition(agg.count == 2, "Aggregator count is 2");
        assertCondition(agg.minVal == 100.0, "Aggregator minVal is 100");
        assertCondition(agg.maxVal == 200.0, "Aggregator maxVal is 200");
        assertCondition(agg.meanVal == 150.0, "Aggregator meanVal is 150");

        val centroid = agg.getCentroid();
        assertCondition(Math.abs(centroid.lat - 15.0) < 1.0e-5, "Centroid lat is 15.0");
        assertCondition(Math.abs(centroid.lon - 30.0) < 1.0e-5, "Centroid lon is 30.0");

        val env = agg.getEnvelope();
        assertCondition(env.minLat == 10.0 && env.maxLat == 20.0, "Envelope lat bounds match");
        assertCondition(env.minLon == 20.0 && env.maxLon == 40.0, "Envelope lon bounds match");

        Console.OUT.println("PASS: SpatialAggregator tests");
    }

    public static def testDynamicLoadBalancer(): Void {
        val balancer = new DynamicLoadBalancer(4, 1.5);
        // Distribute load with massive hotspot on Place 2
        balancer.recordLoad(0, 100);
        balancer.recordLoad(1, 120);
        balancer.recordLoad(2, 900); // Massive hotspot
        balancer.recordLoad(3, 80);

        assertCondition(balancer.isImbalanced(), "Load balancer flags severe imbalance");

        val partitions = new Rail[PlacePartition](4);
        partitions(0) = new PlacePartition(0, 0L, 250L);
        partitions(1) = new PlacePartition(1, 251L, 500L);
        partitions(2) = new PlacePartition(2, 501L, 750L);
        partitions(3) = new PlacePartition(3, 751L, 1000L);

        val plan = balancer.computeRebalancePlan(partitions);
        assertCondition(plan.isPlanActive, "Rebalance plan generated");

        Console.OUT.println("PASS: DynamicLoadBalancer tests");
    }

    public static def testRaftConsensus(): Void {
        val raft = new ConsensusRaftState(1, 3); // Place 1 of 3
        assertCondition(!raft.isLeader(), "Place 1 starts as follower");

        raft.startElection();
        assertCondition(raft.role == ConsensusRaftState.STATE_CANDIDATE, "Transitioned to candidate");
        assertCondition(raft.currentTerm == 1, "Term incremented to 1");

        // Receive append entries from leader Place 0 on term 2
        val accepted = raft.handleAppendEntries(0, 2, 5);
        assertCondition(accepted, "Accepted higher term append entries");
        assertCondition(raft.role == ConsensusRaftState.STATE_FOLLOWER, "Reverted to follower");
        assertCondition(raft.leaderId == 0L, "Recognizes Place 0 as leader");

        Console.OUT.println("PASS: ConsensusRaftState tests");
    }

    public static def main(args: Rail[String]): Void {
        Console.OUT.println("Running TestSketchesAndTopology...");
        testHyperLogLog();
        testSpatialAggregator();
        testDynamicLoadBalancer();
        testRaftConsensus();
        Console.OUT.println("ALL Sketches and Topology tests passed successfully!");
    }
}
