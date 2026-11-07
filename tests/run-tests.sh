#!/bin/sh
# Smoke tests for the muse-swarm: the fork router against the verdict
# vectors from the pattern this swarm re-implements, and a full
# dry-run of the orchestrator (fixtures in place of model calls).
set -eu
cd "$(dirname "$0")/.."
HOME_DIR=$(pwd)
pass=0; fail=0
check() { # check <name> <expected> <actual>
    if [ "$2" = "$3" ]; then echo "PASS $1"; pass=$((pass + 1));
    else echo "FAIL $1: expected [$2] got [$3]"; fail=$((fail + 1)); fi
}

# --- fork router: the diagram's own session values ---
out=$(printf 'which-file 0.81\nwhich-tool 0.83\nretry-or-stop 0.55\n' | ./fork)
check fork-sharp-file "verdict which-file p=0.81 SHARP" "$(printf '%s\n' "$out" | sed -n 1p)"
check fork-sharp-tool "verdict which-tool p=0.83 SHARP" "$(printf '%s\n' "$out" | sed -n 2p)"
check fork-split-retry "verdict retry-or-stop p=0.55 SPLIT" "$(printf '%s\n' "$out" | sed -n 3p)"
edge=$(printf 'at-threshold 0.80\nbelow 0.79\n' | ./fork)
check fork-edge-sharp "verdict at-threshold p=0.80 SHARP" "$(printf '%s\n' "$edge" | sed -n 1p)"
check fork-edge-split "verdict below p=0.79 SPLIT" "$(printf '%s\n' "$edge" | sed -n 2p)"
if printf 'bogus line\n' | ./fork >/dev/null 2>&1; then rc=0; else rc=$?; fi
check fork-malformed-exit "2" "$rc"

# --- orchestrator dry-run: full flow, fixture replies ---
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp/repo"
git -C "$tmp/repo" config user.email test@example.invalid
git -C "$tmp/repo" config user.name swarm-test
echo seed > "$tmp/repo/seed.txt"
git -C "$tmp/repo" add seed.txt
git -C "$tmp/repo" commit -qm seed

SWARM_DRYRUN=1 ./swarm.sh run "test task" "$tmp/repo" > "$tmp/run.out"
v="$tmp/repo/.swarm/verdicts.txt"
check dryrun-verdict-1 "verdict which-file p=0.81 SHARP" "$(sed -n 1p "$v")"
check dryrun-verdict-2 "verdict which-tool p=0.83 SHARP" "$(sed -n 2p "$v")"
check dryrun-verdict-3 "verdict retry-or-stop p=0.55 SPLIT" "$(sed -n 3p "$v")"
check dryrun-plan-gate "1" "$(grep -c 'advisor plan-gate advice=plan' "$tmp/repo/.swarm/session.log")"
check dryrun-done-gate "1" "$(grep -c 'advisor done-gate advice=sign off' "$tmp/repo/.swarm/session.log")"
chain=$(./swarm.sh verify "$tmp/repo" | sed 's/ .*//' )
check dryrun-chain "CHAIN" "$chain"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
