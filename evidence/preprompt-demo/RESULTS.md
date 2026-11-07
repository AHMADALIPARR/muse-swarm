# Pre-prompt demo — results (run 2026-11-07 ~00:43–00:50 UTC, this VM)

Same task, same runner, same seed. Task: three workers report on
"fix the parser crash" (search p=0.81, grep p=0.83, audit p=0.55,
test suite NOT run). The correct decision block is:

```
PLAN: apply the search map, patch the grep sites, rerun the audit
VERDICT search SHARP p=0.81
VERDICT grep SHARP p=0.83
VERDICT audit SPLIT p=0.55
DONE
```

Runner: `~/workspace/.tools/llama.cpp/build/bin/llama-cli`,
`-n 220 --temp 0 -s 42 -c 1024 -t 4 --no-display-prompt --log-disable`.
Bare = `-f task.txt` only. Book = `--system-prompt-file book.md -f task.txt`.

## Scoreboard

| Run | Model | Prompt | Result |
| --- | --- | --- | --- |
| `out-bare.raw` (earlier) | Gemma-2-2b-it Q4_K_M | bare | FAIL — essay about the crash, invents next steps, never issues a decision block, runs off the end |
| `out-book.raw` (this run) | Gemma-2-2b-it Q4_K_M | book.md (76 lines, 2,922 bytes) | PASS — exact decision block above, nothing after DONE |
| `out-llama-bare.raw` | Hermes-3-Llama-3.2-3B Q4_K_M (Llama 3.2 base) | bare | FAIL — numbered flowchart, invents confidences p=0.19 / 0.45 / 0.60, never issues a decision block, cut off at 220 tokens |
| `out-llama-book.raw` | Hermes-3-Llama-3.2-3B Q4_K_M | book.md | PASS — exact decision block above, same five lines as Gemma+book (diff: Gemma's `DONE` line carries one trailing space) |

Speeds: Gemma book 17.8 t/s prompt / 2.2 t/s gen; Llama book
16.3 / 2.8 t/s. Both runs exited 0.

## What this shows

1. The behavior lives in the book, not the weights. Two different
   open models (Gemma 2B, Llama-3.2 3B) produce the same five-line
   verdict block under the same 76-line book (one trailing space
   apart on the DONE line), and both fail without it — in different
   ways (essay vs flowchart, different invented numbers). Swap the
   weights, keep the book, keep the seat.
2. The book is ~2.9 KB. The leaked Claude file the user remembers
   is ~120 KB (see below). The operative core — fork rule, output
   contract, no-invention rule — fits in 76 lines. The other ~117 KB
   is product surface, not agent magic.
3. Bare models don't just underperform; they hallucinate the
   numbers the fork layer is supposed to route on. Llama-bare
   invented p=0.19/0.45/0.60 for facts the task stated. That is the
   failure the book exists to prevent: an unrun audit can never be
   SHARP, and confidences come from workers, never from the lead's
   imagination.

## The "1,000 lines" file, checked

The user's memory maps to the Claude Fable 5 system-prompt
extraction published 2026-06-10 by Pliny the Liberator
(CL4R1T4S repo): 1,585 lines, 120,040 chars, ~30,000 tokens,
72 named sections, 18 tool definitions. Anthropic has not
confirmed it; treat as claimed, not confirmed. Anthropic does
publish official Opus 4 / Sonnet 4 consumer prompts in its
release notes — those are the checkable "Opus one".

Where its 120,040 chars go (per the section-by-section count):
tool definitions & schemas 30%, search & citation rules 25%,
behavior/safety/wellbeing 17%, identity 13%, computer use &
file handling 10%, memory/storage/MCP 6%. Identity — "The
assistant is Claude, created by Anthropic" — lands at line
1,351 of 1,585. Two details that matter for the user's thesis:
the prompt names injection attacks in plain English, and its
oddly specific rules read like shipped incident fixes (a dead
helpline number, a stale-search worked example). That is a
product prompt as a changelog — the same shape as the book's
"same error twice is a plan error" rule, at 40x the size.

What does NOT transfer: the constitution is not in the prompt.
Per the 2026-11-01 analysis, Constitutional AI is trained into
the weights via critique/revision data; no prompt file contains
it. The book replaces the *product* layer (tools, format,
routing, refusal discipline), not the trained-in governance —
and on the user's own terms that is the point: the governance
is the landlord's ceiling, the product layer is reproducible
on owned iron.

## The Meta / Llama / Torch mapping ("lytorch" read as Llama + PyTorch)

No product called "lytorch" was found; read as the Meta
PyTorch-native Llama stack, all open, all zero-rent:

- **Llama** — the weights. Hermes-3-Llama-3.2-3B ran above on
  this VM; Llama 3.2 is the same family the swarm's lead/worker
  seats default to (`llama3.2` / `llama3.2:3b` in README.md).
- **Ollama** — the serving layer the swarm already defaults to
  (`http://localhost:11434/v1` per seat).
- **torchtune** — PyTorch-native fine-tuning (LoRA/QLoRA/full,
  SFT/DPO/GRPO) for Llama 3/3.1/3.2/3.3/4: the route if the book
  ever needs to be baked into weights instead of carried as a
  prompt. Not installed here; named, not claimed as run.
- **torchtitan** — PyTorch-native large-scale pre-training for
  Llama 3/3.1: the route if the weights themselves need to be
  rebuilt. Same caveat.
- **torchchat** — run LLMs (incl. Llama 3.2) from Python, C/C++,
  iOS/Android: the on-device route. Note: no longer under active
  development; see its repo notice before depending on it.

## Limits (honest)

- One task, temp 0, seed 42, n=220, two small (2–3B) models.
  A bigger Llama (70B) or a harder task could separate the
  models; this demo separates bare from book, not Gemma from
  Llama.
- No live Ollama/Jetson run yet and no Meta endpoint wired —
  same limit as STATUS.md. These runs are local llama.cpp on
  this VM, not the swarm's `swarm.sh run` flow.
- The Fable 5 file is unverified; the Opus 4 official prompt
  was not diffed line-by-line here — the mapping above is
  against the published section budget, not a full read.
