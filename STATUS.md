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
