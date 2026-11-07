# J-Lens in muse-swarm — status

## Received (2026-11-06, owner paste in chat)

- `jlens.mjs` — the main file, produced by Claude (the swarm agent) under the owner direction, per owner statement 2026-11-06 (SNAPKITTYWEST/foundry-intel,
  `tools/jlens/`, private repo). Stored verbatim as received.
- AS RECEIVED, the file ends mid-statement: the final
  `main().catch((e) => {` block closes with
  `console.error('J-Lens fatal:', e.message)` and no closing lines.
  The paste is truncated at the tail (confirmed against the chat
  record) — the missing lines exist in the owner's repo copy.
  Nothing was invented to complete it.

## What it is

A behavioral Jacobian probe: TPS (token perturbation sensitivity),
TSP (temperature shadow probe, H_J_proxy = KL(T1||T0)), PBEM (probe
battery entropy measurement) — run against the public Anthropic
Messages API as measurement subject and against local Ollama with
logprob ground truth. Every record is WORM-sealed; a SYNTH-008 gate
verdicts each record EVIDENCE or SILENCE. An offline mode
(--activate-claude-jspace) loads the digital twin brain's j_space +
the claude_j_space_extract and seals an activation record with zero
API calls.

## Missing pieces (needed to run)

- lib/api.mjs, lib/worm.mjs, lib/synth008.mjs, lib/stats.mjs
- techniques/tsp.mjs, techniques/tps.mjs, techniques/pbem.mjs
- The tail of jlens.mjs itself (final catch lines)
- For activation mode: CLAUDE_J_SPACE.md, claude_j_space_extract.json,
  and tools/twin/digital-twin-brain.json from the repo root
- The blend the owner named (not yet identified among the above)

## Verification state

Nothing here has been executed: the imports do not exist yet in
this tree, and the main file is incomplete as received. The
self-test (`--self-test`) is the first check once lib/ lands.

## Intake log

- 2026-11-06: techniques/pbem.mjs described by owner paste (body
  complete-looking; header cut). New dependency learned:
  embeddings/local-embed.mjs; lib exports callClaude/callOllama,
  synth008 includeInEntropy, stats meanPairwiseDistance/variance.
- 2026-11-06: techniques/tps.mjs described by owner paste (header
  cut). TPS = per-token perturbation sensitivity, the Jacobian made
  literal (dOutput/dToken_i, composite of embedding distance and
  length delta), reporting the top load-bearing tokens. New exports
  learned: api roughTokens, stats cosineDistance.
- Placeholders, not code, stand in techniques/ until byte-exact
  files arrive: owner code is never re-typed from a chat paste.
