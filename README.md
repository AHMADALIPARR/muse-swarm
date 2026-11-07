# muse-swarm

A four-seat agent swarm that runs on endpoints the operator owns:
an advisor, a lead, a typed-decision fork layer, and a worker swarm,
with every step written to a hash-chained session ledger. It is the
swarm shape the metered tools sell — advisor, lead, subagent swarm,
decision router — rebuilt Ollama-and-Meta style: local models by
default, Meta models in any seat by configuration, no seat rented
from Anthropic.

## The seats

| Seat | Does | Default model | Card |
| --- | --- | --- | --- |
| advisor | reads the whole session; speaks only at the PLAN and DONE gates; never writes code | `nemotron-super` | `roles/advisor.txt` |
| lead | decomposes the task, applies verdicts, edits, runs tests, verifies | `llama3.2` | `roles/lead.txt` |
| workers | search (map the repo), grep (find call sites), audit (run the checks) — each in its own git worktree, each scoring its own proposal | `llama3.2:3b` | `roles/search.txt`, `roles/grep.txt`, `roles/audit.txt` |
| fork | the typed-decision layer, in C (`fork.c`): a worker proposal at p ≥ 0.80 is SHARP and runs in code; below that it is SPLIT and escalates to the lead | — | — |

The fork is the abstain rule of the typed-decision engine as a
router: a decision the swarm is sure of is a verdict, and a decision
it is split on is a proposal to the lead, never a coin flip.

The role cards are persona hooks in the Ghost Mesh sense: the seat
lives in the card, not in the weights. Drop a different model into a
seat and the seat behaves the same, because the card, the ledger,
and the verdict rules are the connectome.

## Endpoints

Every seat is an OpenAI-shaped chat endpoint plus a model name:

```
ADVISOR_BASE / ADVISOR_MODEL     LEAD_BASE / LEAD_MODEL
WORKER_BASE  / WORKER_MODEL      *_API_KEY (optional, per seat)
```

The default base for every seat is Ollama at
`http://localhost:11434/v1`. Setting a seat's base and model to a
Meta endpoint puts a Muse in that seat; its `*_API_KEY` is read from
the environment at call time and is never written to the ledger or
to disk.

## Running it

```
make            # builds the fork router
make test       # router vectors + a full dry-run of the flow
./swarm.sh run "the task" [repo-dir]
./swarm.sh verify [repo-dir]
```

`run` executes the flow in a git repository: advisor PLAN gate,
three workers in fresh worktrees, fork verdicts over their scored
proposals, the lead's review, and the advisor DONE gate over the
full ledger. State lands in `<repo>/.swarm/`; `verify` recomputes
the ledger's hash chain. `SWARM_DRYRUN=1` runs the identical flow
on the canned replies in `tests/fixtures/`.

## License

SNAPKITTY OPAQUE SOURCE LICENSE v1.0 — see `LICENSE`.
