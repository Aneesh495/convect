/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.topology.ConsensusRaftState
 *
 * Distributed consensus state tracker for cluster membership epochs,
 * partition leases, and log commit indices across X10 Places.
 */

package convect.core.topology;

public class ConsensusRaftState {

    public static val STATE_FOLLOWER: Long = 0;
    public static val STATE_CANDIDATE: Long = 1;
    public static val STATE_LEADER: Long = 2;

    public val placeId: Long;
    public val clusterSize: Long;

    public var currentTerm: Long;
    public var votedFor: Long;
    public var role: Long;
    public var leaderId: Long;

    public var commitIndex: Long;
    public var lastApplied: Long;
    public var epochTimestampMs: Long;

    public def this(placeId: Long, clusterSize: Long) {
        this.placeId = placeId;
        this.clusterSize = clusterSize;
        this.currentTerm = 0;
        this.votedFor = -1;
        this.role = (placeId == 0L) ? STATE_LEADER : STATE_FOLLOWER;
        this.leaderId = 0L;
        this.commitIndex = 0L;
        this.lastApplied = 0L;
        this.epochTimestampMs = System.currentTimeMillis();
    }

    /**
     * Advance term and transition to candidate state during leader election.
     */
    public def startElection(): Void {
        this.currentTerm++;
        this.role = STATE_CANDIDATE;
        this.votedFor = this.placeId;
        this.leaderId = -1L;
    }

    /**
     * Process RequestVote RPC from a peer place.
     */
    public def handleRequestVote(candidateId: Long, term: Long, lastLogTerm: Long, lastLogIndex: Long): Boolean {
        if (term > this.currentTerm) {
            this.currentTerm = term;
            this.role = STATE_FOLLOWER;
            this.votedFor = -1L;
        }

        if (term == this.currentTerm && (this.votedFor == -1L || this.votedFor == candidateId)) {
            // Check log up-to-date criteria
            if (lastLogIndex >= this.commitIndex) {
                this.votedFor = candidateId;
                return true;
            }
        }
        return false;
    }

    /**
     * Process heartbeat or AppendEntries RPC from current leader.
     */
    public def handleAppendEntries(leaderPlaceId: Long, term: Long, leaderCommit: Long): Boolean {
        if (term < this.currentTerm) {
            return false;
        }
        this.currentTerm = term;
        this.role = STATE_FOLLOWER;
        this.leaderId = leaderPlaceId;

        if (leaderCommit > this.commitIndex) {
            this.commitIndex = leaderCommit;
        }
        return true;
    }

    public def isLeader(): Boolean {
        return this.role == STATE_LEADER;
    }
}
