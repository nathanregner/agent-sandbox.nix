#!/usr/bin/env bash
# Test: stateDirs/stateFiles that are symlinks to paths outside $HOME are accessible
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS=$(uname)
source "$SCRIPT_DIR/lib.sh"

if [ "$OS" != "Darwin" ]; then
  echo "Skipping symlink-state tests (Darwin only)"
  exit 0
fi

SANDBOXED=$(nix-build --no-out-link "$SCRIPT_DIR/symlink-state.nix")
SHELL="$SANDBOXED/bin/sandboxed-bash-symlink-state"
run() { "$SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }

echo "=== Symlink state tests (Darwin) ==="
echo

# Create real targets outside $HOME (in /tmp)
REAL_DIR=$(mktemp -d)
REAL_FILE=$(mktemp)
trap 'rm -rf "$REAL_DIR" "$REAL_FILE" "$HOME/.test-symlink-dir" "$HOME/.test-symlink-file"' EXIT

# Point stateDirs/stateFiles at these targets via symlinks in $HOME
ln -sfn "$REAL_DIR"  "$HOME/.test-symlink-dir"
ln -sfn "$REAL_FILE" "$HOME/.test-symlink-file"

TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT
cd "$TESTDIR"

expect_ok "can write into stateDir whose path is a symlink" \
  "echo ok > \$HOME/.test-symlink-dir/probe && cat \$HOME/.test-symlink-dir/probe"
expect_ok "can write to stateFile whose path is a symlink" \
  "echo ok > \$HOME/.test-symlink-file && cat \$HOME/.test-symlink-file"

print_results
exit_status
