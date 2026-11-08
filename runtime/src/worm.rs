//! The WORM block and its seal: the owner's struct, verbatim.
//! The seal is SHA-256 over prev_hash ‖ node_id ‖ task_hash ‖
//! payload_hash ‖ energy_state.to_le_bytes() — the signature is
//! NOT part of the seal (it signs the seal). His snippet named
//! the `sha2` crate; this crate is zero-dependency by his own
//! rule, so the seal runs on the crate's FIPS-verified SHA-256
//! (src/sha256.rs). The byte layout — and therefore every seal —
//! is identical, and the suite cross-checks it against the
//! Erlang verifier, the C node, and an independent hash.

use crate::sha256::sha256;

// The binary layout of the WORM Block in the Rust Runtime
#[repr(C)]
pub struct WormBlock {
    pub prev_hash: [u8; 32],       // The SHA-256 of the parent state
    pub node_id: [u8; 16],         // Cryptographic ID of the Jetson claiming the lock
    pub task_hash: [u8; 32],       // The hash of the .mkr ticket
    pub payload_hash: [u8; 32],    // Hash of the generated code/critique
    pub energy_state: f32,         // The Frustration Hamiltonian value
    pub signature: [u8; 64],       // Ed25519 signature from the Jetson node
}

impl WormBlock {
    /// Computes the WORM seal for this state transition
    pub fn compute_seal(&self) -> [u8; 32] {
        let mut preimage = [0u8; 116];
        preimage[0..32].copy_from_slice(&self.prev_hash);
        preimage[32..48].copy_from_slice(&self.node_id);
        preimage[48..80].copy_from_slice(&self.task_hash);
        preimage[80..112].copy_from_slice(&self.payload_hash);
        preimage[112..116].copy_from_slice(&self.energy_state.to_le_bytes());
        sha256(&preimage)
    }

    /// The 180-byte wire form (bus/worm.hrl): fields in struct
    /// order, energy little-endian.
    pub fn to_wire(&self) -> [u8; 180] {
        let mut out = [0u8; 180];
        out[0..32].copy_from_slice(&self.prev_hash);
        out[32..48].copy_from_slice(&self.node_id);
        out[48..80].copy_from_slice(&self.task_hash);
        out[80..112].copy_from_slice(&self.payload_hash);
        out[112..116].copy_from_slice(&self.energy_state.to_le_bytes());
        out[116..180].copy_from_slice(&self.signature);
        out
    }

    pub fn from_wire(wire: &[u8; 180]) -> Self {
        let mut energy = [0u8; 4];
        energy.copy_from_slice(&wire[112..116]);
        Self {
            prev_hash: wire[0..32].try_into().unwrap(),
            node_id: wire[32..48].try_into().unwrap(),
            task_hash: wire[48..80].try_into().unwrap(),
            payload_hash: wire[80..112].try_into().unwrap(),
            energy_state: f32::from_le_bytes(energy),
            signature: wire[116..180].try_into().unwrap(),
        }
    }
}

/// C ABI: the shared binary transition logic. The Erlang side
/// reaches the same computation through the C node; the Lean 4
/// formalization (worm/Transition.lean) proves the transition's
/// properties over this layout.
///
/// # Safety
/// `block` must point to a valid 180-byte WormBlock and `out`
/// to 32 writable bytes.
#[no_mangle]
pub unsafe extern "C" fn worm_block_seal(block: *const WormBlock, out: *mut u8) {
    let seal = (*block).compute_seal();
    core::ptr::copy_nonoverlapping(seal.as_ptr(), out, 32);
}

#[cfg(test)]
mod tests {
    use super::*;

    pub fn fixture() -> WormBlock {
        WormBlock {
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
        }
    }

    #[test]
    fn wire_layout_matches_the_bus_format() {
        let b = fixture();
        let w = b.to_wire();
        assert_eq!(w.len(), 180);
        assert_eq!(&w[0..32], &[7u8; 32]);
        assert_eq!(w[47], 1); // node id tail
        assert_eq!(w[79], 2); // task hash tail
        assert_eq!(w[111], 3); // payload hash tail
        assert_eq!(&w[112..116], &[0, 0, 0x80, 0x3f]); // 1.0f LE
        let back = WormBlock::from_wire(&w);
        assert_eq!(back.compute_seal(), b.compute_seal());
    }

    #[test]
    fn seal_ignores_the_signature() {
        let mut b = fixture();
        let s1 = b.compute_seal();
        b.signature = [0xabu8; 64];
        assert_eq!(b.compute_seal(), s1);
    }

    #[test]
    fn seal_matches_the_shared_fixture() {
        // The same fixture block is sealed by the Erlang
        // verifier and the C node in the bus suite; the suite
        // compares all three against an independent SHA-256.
        let seal = fixture().compute_seal();
        let hex: String = seal.iter().map(|b| format!("{:02x}", b)).collect();
        assert_eq!(
            hex,
            "065549abeaef063101db2e10e48d9b4334b6151fe3db0d13d3b20bcf9aca2d68"
        );
    }
}
