//! mkr-runtime — the Jetson-side runtime for the muse swarm:
//! Deterministic Silence admission, the PagedAttention block
//! table over a static VRAM arena, the zero-copy FFI seam to
//! the CUDA kernels, the WORM block and its seal, the
//! zero-dependency NATS client, and the KV eviction policy.
//! Zero external crates, by the owner's rule.

extern crate alloc;

pub mod arena;
pub mod ffi;
pub mod kv;
pub mod nats;
pub mod sha256;
pub mod silence;
pub mod worm;
