//! The PagedAttention block table: the owner's code, verbatim.
//!
//! The Orin's 16GB VRAM is a static, pre-allocated arena managed
//! by a lock-free bitset; the block table is strictly a pointer
//! map between a task's logical context and the scattered
//! physical blocks. No heap allocations in the critical path.

use core::sync::atomic::{AtomicU64, Ordering};

pub const BLOCK_SIZE: usize = 16;
// e.g., 65536 blocks * 16 tokens * memory_per_token ~ 10GB KV Cache
pub const MAX_PHYSICAL_BLOCKS: usize = 65536;
pub const BITMAP_SIZE: usize = MAX_PHYSICAL_BLOCKS / 64;

pub struct VramArena {
    // 0 = Free, 1 = Occupied. Atomic u64s allow lock-free O(1) allocation
    free_bitmap: [AtomicU64; BITMAP_SIZE],
}

impl VramArena {
    pub fn new() -> Self {
        Self {
            free_bitmap: [const { AtomicU64::new(0) }; BITMAP_SIZE],
        }
    }

    /// Lock-free physical block allocation via CTZ (Count Trailing Zeros)
    pub fn allocate_block(&self) -> Option<u32> {
        for (i, mask) in self.free_bitmap.iter().enumerate() {
            let current = mask.load(Ordering::Relaxed);
            if current != u64::MAX { // There is a free block
                let bit_idx = (!current).trailing_zeros();
                let prev = mask.fetch_or(1 << bit_idx, Ordering::Acquire);
                if (prev & (1 << bit_idx)) == 0 {
                    return Some((i * 64 + bit_idx as usize) as u32);
                }
            }
        }
        None // OOM: Triggers the Frustration Hamiltonian eviction
    }

    pub fn free_block(&self, block_id: u32) {
        let idx = (block_id / 64) as usize;
        let bit_idx = block_id % 64;
        self.free_bitmap[idx].fetch_and(!(1 << bit_idx), Ordering::Release);
    }

    /// Blocks currently occupied (popcount over the bitmap).
    pub fn allocated_count(&self) -> usize {
        self.free_bitmap
            .iter()
            .map(|m| m.load(Ordering::Relaxed).count_ones() as usize)
            .sum()
    }
}

impl Default for VramArena {
    fn default() -> Self {
        Self::new()
    }
}

pub struct MkrSequence {
    /// WORM-sealed ledger hash from the Erlang NATS bus (#sha256:...)
    pub task_hash: [u8; 32],

    /// Array index is the Logical Block ID. Value is the Physical Block ID.
    /// Pre-allocated to a maximum context limit to prevent heap resizing.
    pub block_map: [u32; 2048],

    /// Current number of physical blocks allocated to this task
    pub allocated_blocks: u32,

    /// Exact token sequence length
    pub sequence_length: u32,
}

impl MkrSequence {
    pub fn new(task_hash: [u8; 32]) -> Self {
        Self {
            task_hash,
            block_map: [0; 2048],
            allocated_blocks: 0,
            sequence_length: 0,
        }
    }

    /// Appends a new token, requesting a physical block from the Arena if needed
    pub fn append_token(&mut self, token_id: u32, arena: &VramArena) -> Result<(), &'static str> {
        let _ = token_id;
        let logical_block_idx = self.sequence_length / BLOCK_SIZE as u32;

        if logical_block_idx >= self.allocated_blocks {
            // Context needs a new physical block
            match arena.allocate_block() {
                Some(physical_id) => {
                    self.block_map[logical_block_idx as usize] = physical_id;
                    self.allocated_blocks += 1;
                },
                None => return Err("VRAM_EXHAUSTED_TRIGGER_HAMILTONIAN"),
            }
        }
        self.sequence_length += 1;
        Ok(())
    }
}

use alloc::collections::BTreeMap;

pub struct BlockTable {
    /// Active tasks currently pinned to this Jetson Orin node
    pub active_tasks: BTreeMap<[u8; 32], MkrSequence>,
}

impl BlockTable {
    pub fn new() -> Self {
        Self {
            active_tasks: BTreeMap::new(),
        }
    }

    /// Generates the flattened physical block routing table for the CUDA kernel
    pub fn generate_cuda_pointer_map(&self) -> Vec<u32> {
        let mut physical_pointers = Vec::with_capacity(self.active_tasks.len() * 2048);
        for sequence in self.active_tasks.values() {
            let active_slice = &sequence.block_map[0..sequence.allocated_blocks as usize];
            physical_pointers.extend_from_slice(active_slice);
        }
        physical_pointers
    }
}

impl Default for BlockTable {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_blocks_are_sequential() {
        let arena = VramArena::new();
        assert_eq!(arena.allocate_block(), Some(0));
        assert_eq!(arena.allocate_block(), Some(1));
        assert_eq!(arena.allocate_block(), Some(2));
        assert_eq!(arena.allocated_count(), 3);
    }

    #[test]
    fn freed_block_is_reused() {
        let arena = VramArena::new();
        let a = arena.allocate_block().unwrap();
        let _b = arena.allocate_block().unwrap();
        arena.free_block(a);
        assert_eq!(arena.allocate_block(), Some(a));
    }

    #[test]
    fn sequence_allocates_a_block_per_16_tokens() {
        let arena = VramArena::new();
        let mut seq = MkrSequence::new([7u8; 32]);
        for i in 0..16 {
            seq.append_token(i, &arena).unwrap();
        }
        assert_eq!(seq.allocated_blocks, 1);
        assert_eq!(seq.sequence_length, 16);
        seq.append_token(16, &arena).unwrap();
        assert_eq!(seq.allocated_blocks, 2);
    }

    #[test]
    fn exhaustion_reports_the_hamiltonian_trigger() {
        // Fill a small corner: allocate every block directly.
        let arena = VramArena::new();
        let mut last = None;
        while let Some(id) = arena.allocate_block() {
            last = Some(id);
        }
        assert_eq!(last, Some((MAX_PHYSICAL_BLOCKS - 1) as u32));
        let mut seq = MkrSequence::new([9u8; 32]);
        assert_eq!(
            seq.append_token(0, &arena),
            Err("VRAM_EXHAUSTED_TRIGGER_HAMILTONIAN")
        );
    }

    #[test]
    fn pointer_map_flattens_allocated_slices_in_key_order() {
        let arena = VramArena::new();
        let mut table = BlockTable::new();
        let mut s1 = MkrSequence::new([1u8; 32]);
        let mut s2 = MkrSequence::new([2u8; 32]);
        for i in 0..20 {
            s1.append_token(i, &arena).unwrap();
        }
        for i in 0..3 {
            s2.append_token(i, &arena).unwrap();
        }
        table.active_tasks.insert([1u8; 32], s1);
        table.active_tasks.insert([2u8; 32], s2);
        let map = table.generate_cuda_pointer_map();
        assert_eq!(map.len(), 3); // 2 blocks for s1 + 1 for s2
        assert_eq!(map, vec![0, 1, 2]);
    }
}
