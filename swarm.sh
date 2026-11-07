#!/bin/sh
# swarm.sh - the muse-swarm orchestrator.
#
# One task flows through the swarm in a fixed order:
#
#   advisor PLAN gate -> workers (search, grep, audit) in worktrees
#   -> fork verdicts -> lead review -> advisor DONE gate
#
# Every step is appended to a hash-chained session ledger at
# <repo>/.swarm/session.log. Nothing is a fact because a model said
# it: the ledger is what happened, and `swarm.sh verify` recomputes
# the chain.
#
# Every role is an OpenAI-shaped chat endpoint plus a model name:
#
#   ADVISOR_BASE / ADVISOR_MODEL   the advisor (reads all, writes nil)
#   LEAD_BASE    / LEAD_MODEL      the lead (edits, tests, verifies)
#   WORKER_BASE  / WORKER_MODEL    the worker swarm (search/grep/audit)
#
# Ollama serves that shape at http://localhost:11434/v1, which is the
# default base for every role: the whole swarm on local models. Point
# a role's base and model at a Meta endpoint and that seat is a Muse;
# that seat's *_API_KEY env var, when set, is sent as a bearer token
# and is never written to the ledger or to disk.
#
# SWARM_DRYRUN=1 runs the full flow on canned role replies from
# tests/fixtures/ - the plumbing (worktrees, verdicts, ledger, chain)
# is identical, only the model calls are fixtures.
#
# Usage:
#   swarm.sh run "<task>" [repo-dir]
#   swarm.sh verify [repo-dir]
set -eu

SWARM_HOME=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FORK="$SWARM_HOME/fork"
DRYRUN=${SWARM_DRYRUN:-0}

BASE_DEFAULT=${SWARM_BASE:-http://localhost:11434/v1}
ADVISOR_BASE=${ADVISOR_BASE:-$BASE_DEFAULT}
LEAD_BASE=${LEAD_BASE:-$BASE_DEFAULT}
WORKER_BASE=${WORKER_BASE:-$BASE_DEFAULT}
ADVISOR_MODEL=${ADVISOR_MODEL:-nemotron-super}
LEAD_MODEL=${LEAD_MODEL:-llama3.2}
WORKER_MODEL=${WORKER_MODEL:-llama3.2:3b}
ADVISOR_API_KEY=${ADVISOR_API_KEY:-}
LEAD_API_KEY=${LEAD_API_KEY:-}
WORKER_API_KEY=${WORKER_API_KEY:-}

# call_role <fixture-key> <base> <model> <key> <role-card> <prompt>
# Prints the role's reply text on stdout.
call_role() {
    fixture=$1; base=$2; model=$3; key=$4; card=$5; prompt=$6
    if [ "$DRYRUN" = "1" ]; then
        cat "$SWARM_HOME/tests/fixtures/$fixture.txt"
        return
    fi
    payload=$(jq -n --arg m "$model" --arg sys "$card" --arg usr "$prompt" \
        '{model:$m, messages:[{role:"system",content:$sys},{role:"user",content:$usr}], temperature:0}')
    if [ -n "$key" ]; then
        reply=$(printf '%s' "$payload" | curl -s -H "Authorization: Bearer $key" -H 'Content-Type: application/json' -d @- "$base/chat/completions")
    else
        reply=$(printf '%s' "$payload" | curl -s -H 'Content-Type: application/json' -d @- "$base/chat/completions")
    fi
    out=$(printf '%s' "$reply" | jq -r '.choices[0].message.content // empty')
    if [ -z "$out" ]; then
        echo "swarm: role call failed ($base, $model): $reply" >&2
        exit 4
    fi
    printf '%s\n' "$out"
}

cmd_run() {
    task=$1
    repo=$(CDPATH= cd -- "${2:-.}" && pwd)
    git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || {
        echo "swarm: $repo is not a git repository (workers need worktrees)" >&2; exit 2; }
    state="$repo/.swarm"
    mkdir -p "$state"
    ledger="$state/session.log"
    : > "$ledger"
    : > "$state/proposals.txt"

    seq=0; prev=GENESIS
    log_line() {
        line="$seq $prev $*"
        printf '%s\n' "$line" >> "$ledger"
        prev=$(printf '%s' "$line" | sha256sum | cut -d' ' -f1)
        seq=$((seq + 1))
    }

    log_line "task $task"

    # PLAN gate: the advisor reads the task before any work starts.
    plan=$(call_role advisor-plan "$ADVISOR_BASE" "$ADVISOR_MODEL" "$ADVISOR_API_KEY" \
        "$(cat "$SWARM_HOME/roles/advisor.txt")" "PLAN gate. Task: $task")
    advice=$(printf '%s\n' "$plan" | sed -n 's/^ADVICE: //p' | head -1)
    log_line "advisor plan-gate advice=${advice:-none}"

    # Workers: one worktree each, proposals scored by the workers.
    for role in search grep audit; do
        wt="$state/wt-$role"
        git -C "$repo" worktree add -f "$wt" HEAD >/dev/null 2>&1
        out=$(call_role "$role" "$WORKER_BASE" "$WORKER_MODEL" "$WORKER_API_KEY" \
            "$(cat "$SWARM_HOME/roles/$role.txt")" "Task: $task (your worktree: $wt)")
        printf '%s\n' "$out" > "$state/out-$role.txt"
        prop=$(printf '%s\n' "$out" | sed -n 's/^PROPOSAL \([a-z-]*\) p=\([0-9.]*\)$/\1 \2/p' | head -1)
        if [ -n "$prop" ]; then
            printf '%s\n' "$prop" >> "$state/proposals.txt"
        else
            echo "swarm: worker $role returned no PROPOSAL line" >&2; exit 4
        fi
        log_line "worker $role done"
        git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
    done

    # Fork layer: typed verdicts over the proposals.
    "$FORK" < "$state/proposals.txt" > "$state/verdicts.txt"
    while IFS= read -r v; do log_line "$v"; done < "$state/verdicts.txt"

    # Lead: applies SHARP as decided, decides every SPLIT, verifies.
    lead=$(call_role lead "$LEAD_BASE" "$LEAD_MODEL" "$LEAD_API_KEY" \
        "$(cat "$SWARM_HOME/roles/lead.txt")" \
        "Task: $task
Worker outputs and fork verdicts are in $state (out-*.txt, verdicts.txt). Review, apply, verify.")
    printf '%s\n' "$lead" > "$state/out-lead.txt"
    log_line "lead review done"

    # DONE gate: the advisor reads the whole session and signs off.
    done_advice=$(call_role advisor-done "$ADVISOR_BASE" "$ADVISOR_MODEL" "$ADVISOR_API_KEY" \
        "$(cat "$SWARM_HOME/roles/advisor.txt")" "DONE gate. Session ledger follows:
$(cat "$ledger")")
    advice=$(printf '%s\n' "$done_advice" | sed -n 's/^ADVICE: //p' | head -1)
    log_line "advisor done-gate advice=${advice:-none}"

    log_line "chain-head $prev"
    echo "--- verdicts"
    cat "$state/verdicts.txt"
    echo "--- ledger: $ledger (head $prev)"
}

cmd_verify() {
    repo=$(CDPATH= cd -- "${1:-.}" && pwd)
    ledger="$repo/.swarm/session.log"
    [ -f "$ledger" ] || { echo "swarm: no ledger at $ledger" >&2; exit 2; }
    prev=GENESIS; expect_seq=0
    while IFS= read -r line; do
        seq=${line%% *}
        rest=${line#* }
        hash=${rest%% *}
        if [ "$seq" != "$expect_seq" ] || [ "$hash" != "$prev" ]; then
            echo "CHAIN BROKEN at line $expect_seq"
            exit 1
        fi
        prev=$(printf '%s' "$line" | sha256sum | cut -d' ' -f1)
        expect_seq=$((expect_seq + 1))
    done < "$ledger"
    echo "CHAIN OK $expect_seq lines head $prev"
}

case "${1:-}" in
    run)    shift; [ $# -ge 1 ] || { echo "usage: swarm.sh run \"<task>\" [repo-dir]" >&2; exit 2; }; cmd_run "$@" ;;
    verify) shift; cmd_verify "$@" ;;
    *)      echo "usage: swarm.sh run \"<task>\" [repo-dir] | swarm.sh verify [repo-dir]" >&2; exit 2 ;;
esac
