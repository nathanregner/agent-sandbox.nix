#!/usr/bin/env bash
# Tests for PATH merging with extraEnv
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS=$(uname)

source "$SCRIPT_DIR/../lib.sh"

SANDBOXED=$(nix-build --no-out-link "$SCRIPT_DIR/../fixtures/path-merge-sandbox.nix")
SHELL="$SANDBOXED/bin/sandboxed-bash-path-merge"

run() { "$SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }
run_output() { "$SHELL" --norc --noprofile -c "$@" 2>/dev/null; }

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/path-merge.XXXXXX")
trap 'rm -rf "$TESTDIR"' EXIT
cd "$TESTDIR"

echo "=== PATH merge tests ($OS) ==="
echo

# --- PATH merging ---
PATH_VAL=$(run_output 'echo $PATH')
if [[ "$PATH_VAL" == "/extra/path:"* ]]; then
	echo "PASS: extraEnv.PATH is prepended to PATH"
	PASS=$((PASS + 1))
else
	echo "FAIL: extraEnv.PATH not prepended (PATH=$PATH_VAL)"
	FAIL=$((FAIL + 1))
fi

# Verify allowedPackages are still in PATH
expect_ok "allowedPackages still in PATH after merge" "ls / > /dev/null"

print_results
exit_status
