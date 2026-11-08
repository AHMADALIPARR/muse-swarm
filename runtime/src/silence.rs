//! Deterministic Silence: the executable form of the Soufflé
//! admission rules (admission/admission.dl).
//!
//! Every node sees the same .mkr ticket on the bus. Nobody
//! shouts: each node first runs the local pre-emption (the
//! Datalog rules, mirrored here line for line), then maps the
//! XOR distance between the task hash and its own node id to a
//! backoff delay. The closest node fires at T=0 and claims the
//! lock; everyone else's timer expires into a world where the
//! lock is already taken, and they stay silent.

/// .decl NodeState(vram_free:number, load_avg:number, node_id:symbol)
/// (the symbol is carried as the 32-byte cryptographic id)
#[derive(Clone, Copy, Debug)]
pub struct NodeState {
    pub vram_free: i64,
    pub load_avg: i64,
    pub node_id: [u8; 32],
}

/// .decl TaskReq(task_id:symbol, vram_req:number, min_compute:number, task_hash:symbol)
#[derive(Clone, Debug)]
pub struct TaskReq {
    pub task_id: String,
    pub vram_req: i64,
    pub min_compute: i64,
    pub task_hash: [u8; 32],
}

/// Rule 1 — the hard filter:
/// Eligible(t) :- TaskReq(t, req_v, req_c, _), NodeState(v, c, _),
///                v >= req_v, c <= req_c.
/// (min_compute is the load ceiling in the owner's rule: a node
/// whose load average exceeds it is invisible.)
pub fn eligible(node: &NodeState, task: &TaskReq) -> bool {
    node.vram_free >= task.vram_req && node.load_avg <= task.min_compute
}

/// Rule 2 — FitnessScore(t, ((v - req_v) * 100) / c)
/// Integer division, matching the .dl on Soufflé `number`.
/// Precondition: eligible(node, task) and load_avg != 0 is the
/// caller's concern exactly as in Datalog (a zero load makes
/// the rule body fail to ground a finite score there; here a
/// zero load is treated as maximally fit).
pub fn fitness_score(node: &NodeState, task: &TaskReq) -> i64 {
    if node.load_avg == 0 {
        return i64::MAX / 2;
    }
    ((node.vram_free - task.vram_req) * 100) / node.load_avg
}

/// Rule 3 — XorDistance via @xor_dist(h, n): the Kademlia
/// metric over the 256-bit hash space.
pub fn xor_distance(task_hash: &[u8; 32], node_id: &[u8; 32]) -> [u8; 32] {
    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = task_hash[i] ^ node_id[i];
    }
    out
}

/// Leading zero bits of the 256-bit distance: 256 for the
/// identical hash, 0 when the top bit differs.
pub fn leading_zeros_256(distance: &[u8; 32]) -> u32 {
    let mut lz = 0u32;
    for &byte in distance.iter() {
        lz += byte.leading_zeros();
        if byte != 0 {
            break;
        }
    }
    lz
}

/// The delay mapping: bucket the distance by its leading zeros
/// and charge 2ms per bucket step. The mathematically closest
/// node (distance with the most leading zeros) waits least;
/// an exact hash match waits 0. This is the local half of the
/// protocol — when several nodes land in one bucket, the
/// Erlang CLAIM lock (bus/lock_server.erl) breaks the tie by
/// Frustration Hamiltonian energy, so a shared bucket can
/// never produce two holders.
pub fn delay_ms(distance: &[u8; 32]) -> u64 {
    (256 - leading_zeros_256(distance)) as u64 * 2
}

/// Rule 4 — BidIntent(t, d) :- XorDistance(t, d),
/// FitnessScore(t, s), s > 10.
/// Returns the delay after which this node may broadcast its
/// CLAIM, or None when the node must stay silent: ineligible,
/// or fitness at or below the owner's threshold of 10.
pub fn bid_intent(node: &NodeState, task: &TaskReq) -> Option<u64> {
    if !eligible(node, task) {
        return None;
    }
    let score = fitness_score(node, task);
    if score > 10 {
        let distance = xor_distance(&task.task_hash, &node.node_id);
        Some(delay_ms(&distance))
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn node(vram: i64, load: i64, id_byte: u8) -> NodeState {
        NodeState {
            vram_free: vram,
            load_avg: load,
            node_id: [id_byte; 32],
        }
    }

    fn task(req_v: i64, req_c: i64, hash_byte: u8) -> TaskReq {
        TaskReq {
            task_id: "t1".to_string(),
            vram_req: req_v,
            min_compute: req_c,
            task_hash: [hash_byte; 32],
        }
    }

    #[test]
    fn hard_filter_drops_saturated_and_overloaded_nodes() {
        // 16GB saturated: vram below the requirement → invisible
        assert!(!eligible(&node(4, 1, 1), &task(8, 4, 2)));
        // load above the ceiling → invisible
        assert!(!eligible(&node(16, 9, 1), &task(8, 4, 2)));
        // exactly at both bounds → eligible (the rule uses >=, <=)
        assert!(eligible(&node(8, 4, 1), &task(8, 4, 2)));
    }

    #[test]
    fn fitness_matches_the_datalog_formula() {
        // ((16 - 8) * 100) / 2 = 400
        assert_eq!(fitness_score(&node(16, 2, 1), &task(8, 4, 2)), 400);
        // ((9 - 8) * 100) / 10 = 10 — at the threshold, not above it
        assert_eq!(fitness_score(&node(9, 10, 1), &task(8, 10, 2)), 10);
    }

    #[test]
    fn bid_intent_threshold_is_strict() {
        // fitness exactly 10 → silence (rule is s > 10)
        assert_eq!(bid_intent(&node(9, 10, 1), &task(8, 10, 2)), None);
        // fitness 11 → a delay
        assert!(bid_intent(&node(19, 10, 1), &task(8, 10, 2)).is_some());
        // ineligible → silence regardless of fitness
        assert_eq!(bid_intent(&node(4, 1, 1), &task(8, 4, 2)), None);
    }

    #[test]
    fn xor_delay_is_zero_for_the_owner_and_monotone_in_distance() {
        let t = task(1, 1, 0xAA);
        // the node whose id equals the task hash: distance 0
        assert_eq!(bid_intent(&node(64, 1, 0xAA), &t), Some(0));
        // a node differing in the top bit waits longest
        let far = bid_intent(&node(64, 1, 0x2A), &t).unwrap(); // 0xAA^0x2A = 0x80...
        let near = bid_intent(&node(64, 1, 0xAB), &t).unwrap(); // 0xAA^0xAB = 0x01...
        assert!(near < far);
        assert_eq!(far, 512);
    }

    #[test]
    fn the_closest_of_three_nodes_wins_the_silence() {
        let t = task(4, 8, 0xF0);
        let delays: Vec<Option<u64>> = [0xF0u8, 0xF1, 0x70]
            .iter()
            .map(|&b| bid_intent(&node(32, 2, b), &t))
            .collect();
        assert_eq!(delays[0], Some(0));
        assert!(delays[1].unwrap() < delays[2].unwrap());
    }
}
