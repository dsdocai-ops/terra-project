#!/usr/bin/env bash
# Headless two-instance smoke (SPEC-networking two-instance steps 1, 2, 3):
#  - steps 1+2: a host and a client connect, both players spawn on both sides,
#    each side's local player walks right so movement crosses the wire in both
#    directions, and the client leaves first so the host sees a peer go.
#  - step 3: a second host/client pair drives the W2-B3 enemy stub end to end —
#    the client asks the host to spawn it through request_debug, the host
#    resolves one partial hit so HP drops 10 -> 7 on both screens (StateSync),
#    the client asks the host to kill it, and enemy_killed fires exactly once.
# Logs land in $OUT (default: a temp dir). Exit 0 when every check passes.
#   GODOT=/path/to/godot tools/smoke_two.sh
set -u
GODOT="${GODOT:-godot}"
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$(mktemp -d)}"
PORT="${PORT:-7777}"
HOST_SECONDS="${HOST_SECONDS:-10}"
CLIENT_SECONDS="${CLIENT_SECONDS:-5}"
HOST3_SECONDS="${HOST3_SECONDS:-14}"
CLIENT3_SECONDS="${CLIENT3_SECONDS:-9}"

fail=0
check() {  # check <file> <grep -E pattern> <description>
  if grep -Eq -- "$2" "$1"; then echo "ok   $3"; else echo "FAIL $3  (missing /$2/ in $1)"; fail=1; fi
}

# --- steps 1+2 ---
"$GODOT" --headless --path "$PROJECT" -- --host "--smoke=$HOST_SECONDS" > "$OUT/host.log" 2>&1 &
HOST_PID=$!
sleep 2
"$GODOT" --headless --path "$PROJECT" -- "--join=127.0.0.1:$PORT" "--smoke=$CLIENT_SECONDS" > "$OUT/client.log" 2>&1 &
CLIENT_PID=$!
wait $HOST_PID $CLIENT_PID

# ENet hands clients a random peer id; read it from the client's own log.
CLIENT_ID=$(grep -Eo 'connected to host as peer [0-9]+' "$OUT/client.log" | grep -Eo '[0-9]+$' | head -1)
if [ -z "$CLIENT_ID" ]; then echo "FAIL client never connected"; echo "logs: $OUT"; exit 1; fi
echo "ok   client connected as peer $CLIENT_ID"

check "$OUT/host.log"   '\[net\] hosting on port'                     "host opened the server"
check "$OUT/host.log"   "\[net\] peer $CLIENT_ID joined"              "host saw the client join"
check "$OUT/host.log"   '\[spawn\] Player1 spawned'                   "host spawned its own player"
check "$OUT/host.log"   "\[spawn\] Player$CLIENT_ID spawned"          "host spawned the client's player"
check "$OUT/client.log" '\[spawn\] Player1 spawned'                   "client received the host's player"
check "$OUT/client.log" "\[spawn\] Player$CLIENT_ID spawned"          "client received its own player"
check "$OUT/host.log"   'peer 1 sees 2 player'                        "host sees both players"
check "$OUT/client.log" "peer $CLIENT_ID sees 2 player"               "client sees both players"
check "$OUT/host.log"   '\[smoke\] autowalk armed on Player1'         "host autowalk armed"
check "$OUT/client.log" "\[smoke\] autowalk armed on Player$CLIENT_ID" "client autowalk armed"
check "$OUT/host.log"   "\[net\] peer $CLIENT_ID left"                "host saw the client leave"

# Movement across the wire: the last logged x of a player must exceed the
# first logged x by a clear margin.
moved() {  # moved <file> <player name>
  local first last
  first=$(grep -Eo "$2=\(-?[0-9.]+" "$1" | head -1 | sed 's/.*(//')
  last=$(grep -Eo "$2=\(-?[0-9.]+" "$1" | tail -1 | sed 's/.*(//')
  [ -n "$first" ] && [ -n "$last" ] && awk -v a="$first" -v b="$last" 'BEGIN { exit !(b > a + 50) }'
}
if moved "$OUT/host.log" "Player$CLIENT_ID";   then echo "ok   client's input moved its player on the host (InputSync)"; else echo "FAIL Player$CLIENT_ID did not move on the host"; fail=1; fi
if moved "$OUT/client.log" "Player1";          then echo "ok   host's movement of Player1 reached the client (StateSync)"; else echo "FAIL Player1 did not move on the client"; fail=1; fi
if moved "$OUT/client.log" "Player$CLIENT_ID"; then echo "ok   client's own player moved locally (prediction + reconcile)"; else echo "FAIL Player$CLIENT_ID did not move on the client"; fail=1; fi

# --- step 3 ---
# Give the first pair's sockets a beat to release before rebinding $PORT.
# --debug-tools ensures the host's DebugConsole executes request_debug lines.
sleep 1
"$GODOT" --headless --path "$PROJECT" -- --host --debug-tools "--smoke3=$HOST3_SECONDS" > "$OUT/host3.log" 2>&1 &
HOST3_PID=$!
sleep 2
"$GODOT" --headless --path "$PROJECT" -- "--join=127.0.0.1:$PORT" --debug-tools "--smoke3=$CLIENT3_SECONDS" > "$OUT/client3.log" 2>&1 &
CLIENT3_PID=$!
wait $HOST3_PID $CLIENT3_PID

check "$OUT/host3.log"   '\[smoke3\] armed on peer 1 \(host\)'         "host3 armed the step-3 driver"
check "$OUT/client3.log" '\[smoke3\] armed on peer [0-9]+ \(client\)'  "client3 armed the step-3 driver"
check "$OUT/client3.log" '\[smoke3\] client requested spawn grub 1'      "client3 asked the host to spawn the enemy"
check "$OUT/host3.log"   '\[console\] spawn grub 1 .* -> spawned 1 grub' "host3 ran the spawn through the console"
check "$OUT/host3.log"   '\[smoke3\] host sees Enemy[0-9]+ hp=10'        "host3 saw the spawned enemy at full HP"
check "$OUT/client3.log" '\[smoke3\] client sees Enemy[0-9]+ hp=10'      "client3 received the enemy via the spawner"
check "$OUT/host3.log"   '\[smoke3\] host resolved hit on Enemy[0-9]+ hp 10 -> 7 \(resolved=true\)' "host3 resolved one hit (HP 10 -> 7)"
check "$OUT/client3.log" '\[smoke3\] client sees Enemy[0-9]+ hp=7'       "client3 saw the HP drop over StateSync"
check "$OUT/host3.log"   '\[smoke3\] host sees Enemy[0-9]+ hp=7'         "host3 still sees HP 7 after the hit"
check "$OUT/client3.log" '\[smoke3\] client requested kill'              "client3 asked the host to kill the enemy"
check "$OUT/host3.log"   '\[console\] kill .* -> killed 1 enem'         "host3 ran the kill through the console"
check "$OUT/host3.log"   '\[smoke3\] enemy_killed emitted 1 time'        "host3 registered the kill exactly once"
check "$OUT/client3.log" '\[smoke3\] client sees Enemy[0-9]+ hp=0 \(dead\)' "client3 saw the death replicated"

echo "logs: $OUT"
exit $fail
