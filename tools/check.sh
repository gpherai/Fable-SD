#!/usr/bin/env bash
# Headless checks: script compilation, data validation, region generation.
# Usage: tools/check.sh [path-to-godot-binary]
set -u
GODOT="${1:-${GODOT:-godot}}"
cd "$(dirname "$0")/.."
filter() { grep -vE "ALSA|snd_|audio_driver|dummy driver|^\s*$" ; }
echo "== scripts =="; timeout 120 "$GODOT" --headless --path . -- --check-scripts 2>&1 | filter | grep -E "SCRIPT ERROR|Parse|Compile|BROKEN|Scripts checked|at: GDScript" ; s1=${PIPESTATUS[0]}
echo "== data ==";    timeout 120 "$GODOT" --headless --path . -- --validate 2>&1 | filter | grep -E "ERR:|Validation|summary" ; s2=${PIPESTATUS[0]}
echo "== regions =="; timeout 600 "$GODOT" --headless --path . -- --gen-test 2>&1 | filter | tail -3 ; s3=${PIPESTATUS[0]}
echo "== smoke =="
smoke_log=$(mktemp)
timeout 900 "$GODOT" --headless --path . -- --smoke > "$smoke_log" 2>&1; s4=$?
filter < "$smoke_log" | grep -E "SMOKE|SCRIPT ERROR|ERROR:|at: "
# a runtime script error does not change Godot's exit code, so count them here
if grep -q "SCRIPT ERROR" "$smoke_log"; then s4=1; fi
rm -f "$smoke_log"
echo "exit codes: scripts=$s1 data=$s2 regions=$s3 smoke=$s4"
[ "$s1" = 0 ] && [ "$s2" = 0 ] && [ "$s3" = 0 ] && [ "$s4" = 0 ]
