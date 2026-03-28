#!/usr/bin/env bash
# Tests for isolateNixStore option (Linux only)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS=$(uname)

# Only run on Linux (isolateNixStore is Linux-only)
if [ "$OS" != "Linux" ]; then
	echo "Skipping no-store-isolation tests (Linux only)"
	exit 0
fi

source "$SCRIPT_DIR/lib.sh"

# Build sandbox with isolateNixStore=false
SANDBOXED=$(nix-build --no-out-link "$SCRIPT_DIR/no-store-isolation-sandbox.nix")
SHELL="$SANDBOXED/bin/sandboxed-bash-no-store-isolation"

run() { "$SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }
run_output() { "$SHELL" --norc --noprofile -c "$@" 2>/dev/null; }

# Also build basic sandbox (isolateNixStore=true) for comparison
SANDBOXED_ISOLATED=$(nix-build --no-out-link "$SCRIPT_DIR/basic-sandbox.nix")
SHELL_ISOLATED="$SANDBOXED_ISOLATED/bin/sandboxed-bash"

run_isolated() { "$SHELL_ISOLATED" --norc --noprofile -c "$@" >/dev/null 2>&1; }

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/no-store-isolation.XXXXXX")
trap 'rm -rf "$TESTDIR"' EXIT
cd "$TESTDIR"

echo "=== Nix store isolation tests ($OS) ==="
echo

# --- isolateNixStore=false ---
# Get the nix binary path (passed via extraEnv)
NIX_BIN=$(run_output 'echo $NIX_BIN')

# Verify we can run nix (which is NOT in allowedPackages)
if run "$NIX_BIN --version"; then
	echo "PASS: can run nix binary outside allowedPackages (isolateNixStore=false)"
	PASS=$((PASS + 1))
else
	echo "FAIL: cannot run nix binary (isolateNixStore=false)"
	FAIL=$((FAIL + 1))
fi

# --- isolateNixStore=true (default) ---
# Verify we CANNOT run nix when store is isolated
if run_isolated "$NIX_BIN --version"; then
	echo "FAIL: should not be able to run nix binary (isolateNixStore=true)"
	FAIL=$((FAIL + 1))
else
	echo "PASS: cannot run nix binary outside allowedPackages (isolateNixStore=true)"
	PASS=$((PASS + 1))
fi

print_results
exit_status
