#!/usr/bin/env bash
# Headless two-instance smoke (SPEC-networking two-instance steps 1, 2, 3):
#  - steps 1+2: a host and a client connect, both players spawn on both sides,
#    each side's local player walks right so movement crosses the wire in both
#    directions, and the client leaves first so the host sees a peer go.
#  - step 3: a second host/client pair drives the W2-B3 enemy stub end to end —
#    the client asks the host to spawn it through request_debug, the host
#    resolves one partial hit so HP drops 10 -> 7 on both screens (StateSync),
#    the client asks the host to kill it, and enemy_killed fires exactly once.
#  - floor sync (SPEC-networking "Seed sync"): two host/client pairs launched
#    with the same --seed must generate the same floor — the two layout_hash
#    values are compared for equality, not merely grepped for presence — and a
#    third pair on a different --seed must land on a different hash.
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

# --- floor sync (SPEC-networking "Seed sync") ---
# The host starts the run once the client has joined, which broadcasts
# floor_ready(seed, floor_index, biome_id, modifiers); each peer generates
# floor 1 locally from that seed and logs the layout_hash it produced. The two
# hashes are compared directly — equality is the assertion, presence is not —
# and a second pair on a different --seed proves the hash actually tracks the
# seed instead of being a constant both peers happen to print.
FLOOR_SEED_A="${FLOOR_SEED_A:-20261020}"
FLOOR_SEED_B="${FLOOR_SEED_B:-987654321}"
FLOOR_HOST_SECONDS="${FLOOR_HOST_SECONDS:-12}"
FLOOR_CLIENT_SECONDS="${FLOOR_CLIENT_SECONDS:-9}"

# The layout_hash a peer logged for floor 1 from `seed`, or empty when it never
# logged one. The seed is part of the pattern, so a peer that generated from
# some other seed does not count as agreeing.
floor_hash() {  # floor_hash <file> <seed>
  grep -Eo "\[floor\] ready seed $2 floor 1 biome [0-9]+ .*layout_hash [0-9]+" "$1" \
    | head -1 | grep -Eo '[0-9]+$'
}

# One host/client pair on a shared --seed; logs land in $OUT/*_floor_<tag>.log.
run_floor_pair() {  # run_floor_pair <tag> <seed>
  sleep 1  # let the previous pair's sockets release before rebinding $PORT
  "$GODOT" --headless --path "$PROJECT" -- --host "--seed=$2" "--smoke-floor=$FLOOR_HOST_SECONDS" > "$OUT/host_floor_$1.log" 2>&1 &
  local host_pid=$!
  sleep 2
  "$GODOT" --headless --path "$PROJECT" -- "--join=127.0.0.1:$PORT" "--seed=$2" "--smoke-floor=$FLOOR_CLIENT_SECONDS" > "$OUT/client_floor_$1.log" 2>&1 &
  local client_pid=$!
  wait $host_pid $client_pid
}

run_floor_pair a "$FLOOR_SEED_A"
check "$OUT/host_floor_a.log"   '\[smoke-floor\] armed on peer 1 \(host\)'         "floor host armed (seed $FLOOR_SEED_A)"
check "$OUT/client_floor_a.log" '\[smoke-floor\] armed on peer [0-9]+ \(client\)'  "floor client armed (seed $FLOOR_SEED_A)"
check "$OUT/host_floor_a.log"   '\[smoke-floor\] host started the run with 2 player' "floor host started the run with the client in it"
FLOOR_HASH_A_HOST=$(floor_hash "$OUT/host_floor_a.log" "$FLOOR_SEED_A")
FLOOR_HASH_A_CLIENT=$(floor_hash "$OUT/client_floor_a.log" "$FLOOR_SEED_A")
if [ -n "$FLOOR_HASH_A_HOST" ] && [ "$FLOOR_HASH_A_HOST" = "$FLOOR_HASH_A_CLIENT" ]; then
  echo "ok   one --seed ($FLOOR_SEED_A) gives one floor: host and client both generated layout_hash $FLOOR_HASH_A_HOST"
else
  echo "FAIL seed $FLOOR_SEED_A layout_hash mismatch: host='$FLOOR_HASH_A_HOST' client='$FLOOR_HASH_A_CLIENT'"; fail=1
fi

run_floor_pair b "$FLOOR_SEED_B"
FLOOR_HASH_B_HOST=$(floor_hash "$OUT/host_floor_b.log" "$FLOOR_SEED_B")
FLOOR_HASH_B_CLIENT=$(floor_hash "$OUT/client_floor_b.log" "$FLOOR_SEED_B")
if [ -n "$FLOOR_HASH_B_HOST" ] && [ "$FLOOR_HASH_B_HOST" = "$FLOOR_HASH_B_CLIENT" ]; then
  echo "ok   one --seed ($FLOOR_SEED_B) gives one floor: host and client both generated layout_hash $FLOOR_HASH_B_HOST"
else
  echo "FAIL seed $FLOOR_SEED_B layout_hash mismatch: host='$FLOOR_HASH_B_HOST' client='$FLOOR_HASH_B_CLIENT'"; fail=1
fi
if [ -n "$FLOOR_HASH_B_HOST" ] && [ "$FLOOR_HASH_B_HOST" != "$FLOOR_HASH_A_HOST" ]; then
  echo "ok   a different --seed ($FLOOR_SEED_B) gives a different floor: $FLOOR_HASH_A_HOST -> $FLOOR_HASH_B_HOST"
else
  echo "FAIL the layout_hash did not change with the seed ('$FLOOR_HASH_A_HOST' vs '$FLOOR_HASH_B_HOST')"; fail=1
fi

echo "logs: $OUT"
exit $fail
