//! Demo driver: seals the shared fixture block (the bus suite
//! compares this seal against the Erlang verifier, the C node,
//! and an independent SHA-256) and prints a block-table
//! flattening, so the crate's behavior is visible without a
//! test harness.

use mkr_runtime::arena::{BlockTable, MkrSequence, VramArena};
use mkr_runtime::worm::WormBlock;

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn main() {
    let fixture = WormBlock {
        prev_hash: [7u8; 32],
        node_id: {
            let mut n = [0u8; 16];
            n[15] = 1;
            n
        },
        task_hash: {
            let mut t = [0u8; 32];
            t[31] = 2;
            t
        },
        payload_hash: {
            let mut p = [0u8; 32];
            p[31] = 3;
            p
        },
        energy_state: 1.0,
        signature: [0u8; 64],
    };
    println!("fixture seal: {}", hex(&fixture.compute_seal()));

    let arena = VramArena::new();
    let mut table = BlockTable::new();
    let mut seq = MkrSequence::new(fixture.compute_seal());
    for i in 0..40 {
        seq.append_token(i, &arena).expect("arena has room");
    }
    println!(
        "sequence: {} tokens, {} blocks",
        seq.sequence_length, seq.allocated_blocks
    );
    table.active_tasks.insert(fixture.compute_seal(), seq);
    println!("pointer map: {:?}", table.generate_cuda_pointer_map());
}
