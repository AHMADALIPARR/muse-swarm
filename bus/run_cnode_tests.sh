#!/bin/sh
# The C-node checks: the Lean verifier node answers over
# distribution, and the custom shell's C-node seal matches its
# local seal. Both nodes are started for the check and killed
# after; node names are the loopback names from the headers.
set -u
cd "$(dirname "$0")"
EI=$(echo /usr/lib/erlang/lib/erl_interface-*/lib)
export LD_LIBRARY_PATH="$EI:${LD_LIBRARY_PATH:-}"
LOGD=$(mktemp -d)
kill_nodes() {
    for d in /proc/[0-9]*; do
        c=$(cat "$d/comm" 2>/dev/null)
        case "$c" in
            lean_verifier*|worm_seal*) kill "${d#/proc/}" 2>/dev/null ;;
        esac
    done
}
cleanup() { kill_nodes; rm -rf "$LOGD"; }
trap cleanup EXIT
fails=0

# --- Lean verifier node ---
setsid ./cnode/lean_verifier_node > "$LOGD/verifier.log" 2>&1 < /dev/null &
sleep 1
if timeout 60 erl -name worm@127.0.0.1 -setcookie secret_worm_cookie \
        -noshell -pa ebin -s verifier_test main > "$LOGD/driver.log" 2>&1; then
    echo "PASS cnode-lean-verifier"
else
    echo "FAIL cnode-lean-verifier"; cat "$LOGD/driver.log"; fails=1
fi
kill_nodes
sleep 1

# --- seal node through the custom shell ---
export WORM_DATA="$LOGD/worm-data"
HEX=$(python3 -c "
tail = bytes([7]*32)
block = tail + (1).to_bytes(16,'big') + (2).to_bytes(32,'big') + (3).to_bytes(32,'big') + bytes([0,0,0x80,0x3f]) + bytes(64)
print(block.hex())")
(sleep 4; printf 'seal %s\nquit\n' "$HEX"; sleep 2) | \
    setsid erl -name worm@127.0.0.1 -setcookie wormseal \
        -noshell -pa ebin -s worm_shell start > "$LOGD/shell.log" 2>&1 &
sleep 1
setsid ./cnode/worm_seal_node worm@127.0.0.1 wormseal > "$LOGD/seal.log" 2>&1 < /dev/null &
sleep 8
LOCAL=$(sed -n 's/.*local: \([0-9a-f]*\).*//p' "$LOGD/shell.log")
CNODE=$(sed -n 's/.*cnode: \([0-9a-f]*\).*//p' "$LOGD/shell.log")
if [ -n "$LOCAL" ] && [ "$LOCAL" = "$CNODE" ]; then
    echo "PASS cnode-seal-matches-local"
else
    echo "FAIL cnode-seal-matches-local local=[$LOCAL] cnode=[$CNODE]"
    cat "$LOGD/shell.log" "$LOGD/seal.log"; fails=1
fi
exit $fails
