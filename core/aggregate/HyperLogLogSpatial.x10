/*
 * Convect Distributed Spatiotemporal Stream Engine
 * Module: core.aggregate.HyperLogLogSpatial
 *
 * Distributed HyperLogLog cardinality estimator for streaming spatial
 * sensors across X10 Places with register merging.
 */

package convect.core.aggregate;

public class HyperLogLogSpatial {

    public val p: Long; // Number of register index bits (e.g., 10 -> 1024 registers)
    public val m: Long; // Number of registers = 2^p
    private val alphaMM: Double;
    private val registers: Rail[Long];

    public def this(precisionBits: Long) {
        this.p = Math.min(16, Math.max(4, precisionBits));
        this.m = 1L << this.p;
        this.registers = new Rail[Long](this.m);

        // Alpha constant calculation
        var alpha: Double = 0.7213 / (1.0 + 1.079 / (m as Double));
        if (m == 16) alpha = 0.673;
        else if (m == 32) alpha = 0.697;
        else if (m == 64) alpha = 0.709;
        this.alphaMM = alpha * (m as Double) * (m as Double);
    }

    public def this() {
        this(10);
    }

    /**
     * 64-bit FNV-1a hash of a string key.
     */
    private static def fnv1a64(key: String): Long {
        var hash: Long = 0xcbf29ce484222325L;
        val fnvPrime: Long = 0x100000001b3L;
        for (i in 0..(key.length() - 1)) {
            val c = key.charAt(i) as Long;
            hash = hash ^ c;
            hash = hash * fnvPrime;
        }
        return hash;
    }

    /**
     * Count leading zeros in trailing bits after the p register bits.
     */
    private def countLeadingZeros(w: Long): Long {
        if (w == 0L) return 64L - p;
        var count: Long = 1;
        var temp: Long = w;
        while ((temp & 0x8000000000000000L) == 0L && count < (64 - p)) {
            count++;
            temp = temp << 1;
        }
        return count;
    }

    /**
     * Add a sensor identifier to the HyperLogLog sketch.
     */
    public def add(sensorId: String): Void {
        val x = fnv1a64(sensorId);
        // Extract top p bits for register index
        val j = (x >>> (64 - p)) as Long;
        // Remaining bits for run length
        val w = x << p;
        val r = countLeadingZeros(w);

        if (r > registers(j)) {
            registers(j) = r;
        }
    }

    /**
     * Merge another HyperLogLog sketch into this one (element-wise max of registers).
     */
    public def merge(other: HyperLogLogSpatial): Void {
        val limit = Math.min(this.m, other.m);
        for (i in 0..(limit - 1)) {
            if (other.registers(i) > this.registers(i)) {
                this.registers(i) = other.registers(i);
            }
        }
    }

    /**
     * Estimate distinct sensor count with small-range linear counting correction.
     */
    public def estimate(): Double {
        var zSum: Double = 0.0;
        var zeroCount: Long = 0;

        for (i in 0..(m - 1)) {
            zSum += 1.0 / Math.pow(2.0, registers(i) as Double);
            if (registers(i) == 0L) {
                zeroCount++;
            }
        }

        var e = alphaMM / zSum;

        // Small range correction (Linear Counting)
        if (e <= 2.5 * (m as Double)) {
            if (zeroCount > 0) {
                e = (m as Double) * Math.log((m as Double) / (zeroCount as Double));
            }
        }
        return e;
    }
}
