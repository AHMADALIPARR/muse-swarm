//! KV cache policy for the 16GB Orin NX: quantization pinning,
//! the bytes-per-token math the pool is sized by, and the
//! deterministic eviction path — a two-phase prune where
//! physical blocks are freed only after the Erlang oracle has
//! accepted the summarization block into the WORM ledger.

use crate::arena::{BlockTable, VramArena, MAX_PHYSICAL_BLOCKS};
use alloc::collections::{BTreeMap, BTreeSet};

/// KV quantization formats (llama.cpp block layouts).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Quant {
    Q8_0,
    Q4_0,
    F16,
}

impl Quant {
    /// Bytes per element, exact: q8_0 packs 32 values into
    /// 34 bytes (fp16 scale + 32 int8), q4_0 packs 32 into 18
    /// (fp16 scale + 16 nibbles-bytes), f16 is 2.
    pub fn bytes_per_element(&self) -> f64 {
        match self {
            Quant::Q8_0 => 34.0 / 32.0,
            Quant::Q4_0 => 18.0 / 32.0,
            Quant::F16 => 2.0,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TaskKind {
    Synthesis,
    Critique,
}

/// The quantization pinned to a task kind. The K cache dictates
/// token relations: for verification (critique) work it is
/// pinned to q8_0 to preserve logical accuracy, while the V
/// cache takes the aggressive q4_0. Weights are quantized
/// independently of this choice.
pub fn kv_quant_for(kind: TaskKind) -> (Quant, Quant) {
    match kind {
        TaskKind::Critique => (Quant::Q8_0, Quant::Q4_0),
        TaskKind::Synthesis => (Quant::Q8_0, Quant::Q4_0),
    }
}

/// A model's KV shape: everything the pool sizing needs.
#[derive(Clone, Copy, Debug)]
pub struct KvShape {
    pub layers: usize,
    pub kv_heads: usize,
    pub head_dim: usize,
}

impl KvShape {
    pub fn bytes_per_token(&self, k: Quant, v: Quant) -> f64 {
        let per_layer = (self.kv_heads * self.head_dim) as f64;
        self.layers as f64 * per_layer * (k.bytes_per_element() + v.bytes_per_element())
    }

    /// Whole tokens the pool holds for this shape under a byte
    /// budget — the number the 90% eviction threshold rides on.
    pub fn tokens_in_budget(&self, k: Quant, v: Quant, budget_bytes: usize) -> usize {
        (budget_bytes as f64 / self.bytes_per_token(k, v)) as usize
    }
}

/// Pool utilization as a fraction of MAX_PHYSICAL_BLOCKS.
pub fn utilization(arena: &VramArena) -> f64 {
    arena.allocated_count() as f64 / MAX_PHYSICAL_BLOCKS as f64
}

/// The 90% threshold: at or above it, the eviction protocol
/// fires (the owner's ~14.4GB line on a 16GB part, expressed
/// against the block pool).
pub fn over_eviction_threshold(arena: &VramArena) -> bool {
    utilization(arena) >= 0.90
}

/// Choose the eviction victim: the active task with the lowest
/// caller-supplied priority (the Frustration Hamiltonian's
/// ranking of what the cluster can most afford to suspend).
/// Ties break toward the task holding the most blocks — the
/// eviction that frees the most room wins.
pub fn select_victim(
    table: &BlockTable,
    priority: &BTreeMap<[u8; 32], f32>,
) -> Option<[u8; 32]> {
    let mut best: Option<([u8; 32], f32, u32)> = None;
    for (hash, seq) in table.active_tasks.iter() {
        let p = priority.get(hash).copied().unwrap_or(0.0);
        let better = match best {
            None => true,
            Some((_, bp, bb)) => p < bp || (p == bp && seq.allocated_blocks > bb),
        };
        if better {
            best = Some((*hash, p, seq.allocated_blocks));
        }
    }
    best.map(|(h, _, _)| h)
}

/// Two-phase deterministic pruning. `propose` marks a task's
/// blocks pending-free — nothing is released, so a rejected or
/// orphaned proposal costs nothing. Only `confirm` (the oracle
/// accepted the summary block; the ledger is the ground truth)
/// frees the physical blocks and drops the sequence.
#[derive(Default)]
pub struct PruneManager {
    pending: BTreeSet<[u8; 32]>,
}

impl PruneManager {
    pub fn new() -> Self {
        Self::default()
    }

    /// Phase 1: mark. Returns the number of blocks that would
    /// be freed, or None if the task is not active.
    pub fn propose(&mut self, table: &BlockTable, task_hash: &[u8; 32]) -> Option<u32> {
        let seq = table.active_tasks.get(task_hash)?;
        self.pending.insert(*task_hash);
        Some(seq.allocated_blocks)
    }

    pub fn is_pending(&self, task_hash: &[u8; 32]) -> bool {
        self.pending.contains(task_hash)
    }

    /// Phase 2a: the oracle accepted — free the blocks.
    /// Returns the number of blocks actually freed.
    pub fn confirm(
        &mut self,
        table: &mut BlockTable,
        arena: &VramArena,
        task_hash: &[u8; 32],
    ) -> Option<u32> {
        if !self.pending.remove(task_hash) {
            return None;
        }
        let seq = table.active_tasks.remove(task_hash)?;
        for i in 0..seq.allocated_blocks as usize {
            arena.free_block(seq.block_map[i]);
        }
        Some(seq.allocated_blocks)
    }

    /// Phase 2b: the oracle rejected (or the append lost the
    /// sequence gate) — unmark; the task's context is untouched.
    pub fn abort(&mut self, task_hash: &[u8; 32]) -> bool {
        self.pending.remove(task_hash)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::arena::MkrSequence;

    #[test]
    fn quant_sizes_are_the_llama_block_layouts() {
        assert_eq!(Quant::Q8_0.bytes_per_element(), 34.0 / 32.0);
        assert_eq!(Quant::Q4_0.bytes_per_element(), 18.0 / 32.0);
        assert_eq!(Quant::F16.bytes_per_element(), 2.0);
    }

    #[test]
    fn verification_pins_k_to_q8() {
        let (k, v) = kv_quant_for(TaskKind::Critique);
        assert_eq!(k, Quant::Q8_0);
        assert_eq!(v, Quant::Q4_0);
    }

    #[test]
    fn bytes_per_token_math() {
        // 32 layers, 8 kv heads, 128 dim: K q8 + V q4
        let shape = KvShape { layers: 32, kv_heads: 8, head_dim: 128 };
        let bpt = shape.bytes_per_token(Quant::Q8_0, Quant::Q4_0);
        // 32 * 1024 * (1.0625 + 0.5625) = 53248
        assert_eq!(bpt, 53248.0);
        // a 10 GiB pool holds 201,649 whole tokens at that rate
        assert_eq!(shape.tokens_in_budget(Quant::Q8_0, Quant::Q4_0, 10 * 1024 * 1024 * 1024), 201649);
    }

    #[test]
    fn prune_is_two_phase_and_only_confirm_frees() {
        let arena = VramArena::new();
        let mut table = BlockTable::new();
        let mut seq = MkrSequence::new([5u8; 32]);
        for i in 0..33 {
            seq.append_token(i, &arena).unwrap();
        }
        table.active_tasks.insert([5u8; 32], seq);
        assert_eq!(arena.allocated_count(), 3);

        let mut prune = PruneManager::new();
        assert_eq!(prune.propose(&table, &[5u8; 32]), Some(3));
        // proposed, not freed: the ledger has not accepted yet
        assert_eq!(arena.allocated_count(), 3);
        assert!(table.active_tasks.contains_key(&[5u8; 32]));

        // abort path: still nothing freed
        assert!(prune.abort(&[5u8; 32]));
        assert_eq!(arena.allocated_count(), 3);

        // confirm path: blocks return to the pool for reuse
        assert_eq!(prune.propose(&table, &[5u8; 32]), Some(3));
        assert_eq!(prune.confirm(&mut table, &arena, &[5u8; 32]), Some(3));
        assert_eq!(arena.allocated_count(), 0);
        assert_eq!(arena.allocate_block(), Some(0));
    }

    #[test]
    fn victim_is_the_lowest_priority_then_the_fattest() {
        let arena = VramArena::new();
        let mut table = BlockTable::new();
        let mut a = MkrSequence::new([1u8; 32]);
        let mut b = MkrSequence::new([2u8; 32]);
        for i in 0..17 {
            a.append_token(i, &arena).unwrap();
        }
        for i in 0..33 {
            b.append_token(i, &arena).unwrap();
        }
        table.active_tasks.insert([1u8; 32], a);
        table.active_tasks.insert([2u8; 32], b);
        let mut prio = BTreeMap::new();
        prio.insert([1u8; 32], 0.5f32);
        prio.insert([2u8; 32], 0.5f32);
        // equal priority: b holds more blocks, b is the victim
        assert_eq!(select_victim(&table, &prio), Some([2u8; 32]));
        prio.insert([1u8; 32], 0.1f32);
        assert_eq!(select_victim(&table, &prio), Some([1u8; 32]));
    }
}
