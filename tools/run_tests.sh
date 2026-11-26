#!/bin/bash
# Runs every test suite against the last commit (not the working tree), in a
# temporary checkout, so what passes is exactly what gets pushed.
# Usage: tools/run_tests.sh [path to Godot]
set -u
GODOT="${1:-${GODOT:-godot}}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$(mktemp -d)"
trap 'git -C "$REPO" worktree remove --force "$DIR" >/dev/null 2>&1; rm -rf "$DIR"' EXIT
git -C "$REPO" worktree add --detach "$DIR" HEAD >/dev/null 2>&1 || { echo "could not check out HEAD"; exit 2; }
if ! git -C "$REPO" diff --quiet HEAD; then
	echo "Note: you have uncommitted changes; these tests run on the last commit without them."
fi
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
failed=0
for t in flow_test loop_test editor_test physics_test; do
	out="$(timeout 600 "$GODOT" --headless --fixed-fps 60 --path "$DIR" "res://tests/$t.tscn" 2>&1)"
	if echo "$out" | grep -q "^0 failure(s)" && ! echo "$out" | grep -q "SCRIPT ERROR\|Parse Error"; then
		echo "PASS  $t"
	else
		echo "FAIL  $t"
		echo "$out" | grep -E "FAIL|SCRIPT ERROR|Parse Error|failure" | head -20
		failed=1
	fi
done
exit $failed
