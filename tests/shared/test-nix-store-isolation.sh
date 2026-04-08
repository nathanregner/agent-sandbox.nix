#!/usr/bin/env bash
# Test that nix store paths outside the closure are not accessible (shared across platforms)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../lib.sh"

SANDBOXED=$(nix-build --no-out-link "$SCRIPT_DIR/../fixtures/nix-store-isolation.nix")
SHELL="$SANDBOXED/bin/sandboxed-bash-store-isolation"

run() { "$SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }
run_output() { "$SHELL" --norc --noprofile -c "$@" 2>/dev/null; }

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/store-isolation.XXXXXX")
trap 'rm -rf "$TESTDIR"' EXIT
cd "$TESTDIR"

echo "=== Nix store isolation tests (shared) ==="
echo

# --- Allowed packages should work ---
expect_ok "can run allowed binary (ls)" "ls / > /dev/null"
expect_ok "can run allowed binary (echo)" "echo hello"

# --- Disallowed package should be inaccessible ---
expect_fail "cannot execute disallowed store path" '"$DISALLOWED_STORE_PATH/bin/hello"'

print_results
exit_status
