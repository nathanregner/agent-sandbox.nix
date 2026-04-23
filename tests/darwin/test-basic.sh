#!/usr/bin/env bash
# Basic sandbox tests (Darwin-specific)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../lib.sh"

SANDBOXED=$(nix-build --no-out-link "$SCRIPT_DIR/../fixtures/basic-sandbox.nix")
SHELL="$SANDBOXED/bin/sandboxed-bash"

run() { "$SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/basic-darwin.XXXXXX")
trap 'rm -rf "$TESTDIR"' EXIT
cd "$TESTDIR"

echo "=== Basic sandbox tests (Darwin) ==="
echo

# --- Darwin-specific tests ---
expect_fail "cannot write to /etc" "touch /etc/test"
expect_ok "can exec /bin/sh subshell" "/bin/sh -c 'echo hello'"

REAL_HOME="/Users/$(whoami)"
expect_fail "cannot read real home" "ls $REAL_HOME/.ssh"

# --- Directory enumeration (readdir blocked, stat allowed) ---
expect_fail "cannot enumerate /Users" "ls /Users/"
expect_fail "cannot enumerate real home dir" "ls $REAL_HOME/"
expect_ok "stat on /Users succeeds (path traversal)" "test -d /Users"
expect_ok "stat on real home succeeds (path traversal)" "test -d $REAL_HOME"

# --- /tmp isolation (prevents tmux attach escape) ---
expect_fail "cannot access /tmp" "ls /tmp/"
expect_fail "cannot access /private/tmp" "ls /private/tmp/"
expect_ok "TMPDIR is writable" 'touch "$TMPDIR/test-file"'
expect_ok "TMPDIR is not under /tmp" '[[ "$TMPDIR" != /tmp* ]] && [[ "$TMPDIR" != /private/tmp* ]]'

print_results
exit_status
