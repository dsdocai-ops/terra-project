#!/usr/bin/env sh
# Launches a host and N clients of Sinkhole side by side on one machine.
# Usage (from the repo root):
#   tools/run_two.sh            # host + 1 client
#   tools/run_two.sh 2          # host + 2 clients
#   GODOT=/path/to/godot tools/run_two.sh
CLIENTS="${1:-1}"
GODOT="${GODOT:-godot}"
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
W=960
H=540

"$GODOT" --path "$PROJECT" --resolution "${W}x${H}" --position 0,40 -- --host &
sleep 1.5

i=1
while [ "$i" -le "$CLIENTS" ]; do
  X=$(( (i % 2) * (W + 10) ))
  Y=$(( 40 + (i / 2) * (H + 40) ))
  "$GODOT" --path "$PROJECT" --resolution "${W}x${H}" --position "${X},${Y}" -- --join=127.0.0.1 &
  sleep 0.5
  i=$((i + 1))
done
wait
