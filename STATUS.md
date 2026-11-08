# STATUS

## Verified (2026-11-06, this machine, gcc -std=c11 -Wall -Wextra)

- `fork` builds with zero errors and zero warnings.
- `make test` passes its full suite: the fork router against the
  verdict vectors of the pattern this swarm re-implements
  (which-file 0.81 SHARP, which-tool 0.83 SHARP, retry-or-stop 0.55
  SPLIT, threshold edge 0.80 SHARP / 0.79 SPLIT, malformed input
  exits 2), and a dry-run of the whole orchestrator flow — PLAN
  gate, three worktree workers, three verdicts in the expected
  pattern, lead review, DONE gate — closing with a session ledger
  whose hash chain recomputes clean under `swarm.sh verify`.

## Evidence (2026-11-06)

- `evidence/preprompt-demo/` holds a four-run test of the book
  pattern behind the role cards: Gemma-2-2b-it and Hermes-3-Llama-
  3.2-3B, each bare and each wearing the same 76-line book, same
  task, same seed, llama.cpp on this machine. Bare runs fail (an
  essay; a flowchart inventing confidences); both book runs emit
  the exact fork decision block. Full transcripts and method in
  `evidence/preprompt-demo/RESULTS.md`.

## Limits

- The dry-run is the verified surface: role replies come from
  `tests/fixtures/`. No live model call has been run from this
  machine — Ollama lives on the operator's hardware (the Jetson,
  whose memory is committed to other work today), and no Meta
  endpoint has been wired yet.
- Live wiring is configuration, not code: set the seat bases and
  models (and a seat's API key env var where the endpoint needs
  one) as the README describes, then run the same `swarm.sh run`.
  The default model names are starting points for the operator's
  own Ollama tags.
- The lead's review step records its decisions in the session
  state; applying code edits from worker worktrees into the target
  repository is the lead model's live behavior, exercised only in
  a live run.
- One task per `run`; sessions do not yet resume across runs.

## Verified (2026-11-07, this machine) — silence, runtime, bus, ledger

- Runtime crate (`runtime/`): 23 cargo tests pass — FIPS
  SHA-256 vectors; the owner's block-table code (allocation,
  free-reuse, per-16-token block growth, exhaustion returning
  `VRAM_EXHAUSTED_TRIGGER_HAMILTONIAN`, pointer-map flattening);
  the WORM seal of the shared fixture block equals
  `065549ab…aca2d68`, the same value the Erlang verifier, the
  C seal node, and an independent SHA-256 produce; HPUB frame
  shape (`HPUB sovereign.ledger.append 45 49` for a 4-byte
  payload at expected sequence 42) against a mock socket, the
  wrong-last-sequence trap, PING→PONG; Deterministic Silence
  fixtures (hard filter bounds, fitness 10 stays silent /
  11 bids, closest node delays 0); KV two-phase prune (propose
  frees nothing, confirm frees, abort frees nothing), victim
  selection, bytes-per-token math; the host FFI flattening.
- Erlang bus (`bus/`): 21 checks pass — the owner's supervision
  tree boots; a consumer replays from last verified sequence
  +1 with his JetStream consumer config; a valid block commits
  and is ACKed; a fork and a sequence gap each crash the worker
  (`invalid_state_transition`, his purge-on-invalid design) and
  the chain does not move; the CLAIM lock admits the first
  claim, rejects higher energy, and is displaced by lower;
  subject partitioning by role.
- C nodes: the Lean verifier node (Lean 4.12 runtime + the
  `@[export]`ed transition predicate from
  `worm/Transition.lean`, which checks clean with its proofs)
  answers over Erlang distribution — admissible block true,
  forked prev false, energy above the ceiling false. The seal
  node's seal equals the Erlang and Rust seals on the shared
  fixture. `bus/worm_verifier.h` is the header both C nodes
  share: identity, wire layout, term protocol, FFI prototype.
- Full suite: `make test` — 18 passed, 0 failed (the original
  12 unchanged).

## Limits (2026-11-07 additions)

- No NATS server runs on this machine: the bus is exercised
  against the connection manager's local sink, which is the
  same code path a network partition takes. The JetStream
  stream and consumer configs ship verbatim in `bus/`; the
  sequence gate is enforced by the oracle-side verifier here
  and by the server's publish expectations on the fleet.
- The CUDA path (`--features jetson`) is not compiled here —
  no nvcc on this machine. The pinned-buffer API and update
  semantics are tested through the host fallback in
  `runtime/src/ffi.rs`; the trampoline
  (`runtime/ffi/paged_attention_launcher.cu`) is the owner's
  code, compiled by build.rs on the Jetson.
- Soufflé itself is not installed here: `admission/admission.dl`
  ships as the owner's baseline, and `runtime/src/silence.rs`
  is its executable mirror, tested on fixtures.
- The Erlang fragments the owner supplied (supervision tree,
  connection clauses, ledger worker core) are verbatim; the
  scaffolding completed around them (state records, protocol
  builders, the store, the registry) is labeled as completion
  in the module headers. Two ei behaviors on this machine are
  load-bearing and commented at the call sites: node identity
  must go through ei_connect_xinit (the plain init mangles a
  full name@host on the wire and the peer closes the
  handshake), and receives must use ei_xreceive_msg
  (ei_receive_msg returns an instant error here).
