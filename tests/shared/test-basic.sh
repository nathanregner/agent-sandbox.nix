#!/usr/bin/env bash
# Basic sandbox isolation and access tests (shared across platforms)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS=$(uname)

source "$SCRIPT_DIR/../lib.sh"

SANDBOXED=$(nix-build --no-out-link "$SCRIPT_DIR/../fixtures/basic-sandbox.nix")
SHELL="$SANDBOXED/bin/sandboxed-bash"

run() { "$SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }
run_output() { "$SHELL" --norc --noprofile -c "$@" 2>/dev/null; }

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/basic.XXXXXX")
trap 'rm -rf "$TESTDIR" "$HOME/.test-ro-dir" "$HOME/.test-ro-file" "$HOME/.test-overlay-dir"' EXIT
cd "$TESTDIR"

# Create read-only test fixtures (must exist before sandbox runs)
mkdir -p "$HOME/.test-ro-dir"
echo "ro-dir-content" > "$HOME/.test-ro-dir/test-file"
echo "ro-file-content" > "$HOME/.test-ro-file"

# Create overlay test fixture (Linux only, must exist before sandbox runs)
if [ "$OS" = "Linux" ]; then
	mkdir -p "$HOME/.test-overlay-dir"
	echo "overlay-original" > "$HOME/.test-overlay-dir/original-file"
fi

echo "=== Basic sandbox tests (shared) ==="
echo

# --- Isolation ---
expect_fail "cannot read ~/.ssh" "ls \$HOME/.ssh"
expect_fail "cannot read ~/.bash_history" "cat \$HOME/.bash_history"
expect_fail "cannot read /root" "ls /root"

# --- Basic access ---
expect_ok "can write to CWD" "touch ./sandbox-test-file && rm ./sandbox-test-file"
if [ "$OS" = "Darwin" ]; then
	# Darwin uses isolated TMPDIR under /private/var/folders, /tmp is blocked
	expect_ok "can write to TMPDIR" 'touch "$TMPDIR/sandbox-test" && rm "$TMPDIR/sandbox-test"'
else
	expect_ok "can write to /tmp" "touch /tmp/sandbox-test && rm /tmp/sandbox-test"
fi
expect_ok "can read /etc/resolv.conf" "cat /etc/resolv.conf > /dev/null"
expect_ok "can run allowed binaries" "ls / > /dev/null"

# --- stateDirs / stateFiles / extraEnv ---
if [ "$(run_output 'echo $TEST_VAR')" = "test-value" ]; then
	echo "PASS: extraEnv variable is accessible"
	PASS=$((PASS + 1))
else
	echo "FAIL: extraEnv variable not accessible"
	FAIL=$((FAIL + 1))
fi

# --- Environment isolation (env -i) ---
export _TEST_HOST_VAR="should-not-propagate"
if [ -z "$(run_output 'echo $_TEST_HOST_VAR')" ]; then
	echo "PASS: host env vars not in extraEnv are not propagated"
	PASS=$((PASS + 1))
else
	echo "FAIL: host env var leaked into sandbox"
	FAIL=$((FAIL + 1))
fi

# --- Read-only state dirs/files ---
# Verify roStateDirs can be read
if [ "$(run_output 'cat $HOME/.test-ro-dir/test-file')" = "ro-dir-content" ]; then
	echo "PASS: roStateDir is readable"
	PASS=$((PASS + 1))
else
	echo "FAIL: roStateDir not readable"
	FAIL=$((FAIL + 1))
fi

# Verify roStateFiles can be read
if [ "$(run_output 'cat $HOME/.test-ro-file')" = "ro-file-content" ]; then
	echo "PASS: roStateFile is readable"
	PASS=$((PASS + 1))
else
	echo "FAIL: roStateFile not readable"
	FAIL=$((FAIL + 1))
fi

# Verify writes to roStateDir fail
expect_fail "cannot write to roStateDir" "touch \$HOME/.test-ro-dir/new-file"

# Verify writes to roStateFile fail
expect_fail "cannot write to roStateFile" "echo test >> \$HOME/.test-ro-file"

# --- Ephemeral HOME (both platforms) ---
expect_ok "home is empty tmpfs" "ls \$HOME"
expect_ok "home tmpfs is writable (ephemeral)" "touch \$HOME/.test-write && rm \$HOME/.test-write"
expect_fail "host dotfiles are not visible" "ls \$HOME/.bashrc"

# --- Platform-specific ---
if [ "$OS" = "Darwin" ]; then
	expect_fail "cannot write to /etc" "touch /etc/test"
	expect_ok "can exec /bin/sh subshell" "/bin/sh -c 'echo hello'"
	REAL_HOME="/Users/$(whoami)"
	expect_fail "cannot read real home" "ls $REAL_HOME/.ssh"
elif [ "$OS" = "Linux" ]; then
	expect_ok "/etc is writable tmpfs (ephemeral)" "touch /etc/test && rm /etc/test"
	expect_fail "cannot read host /etc/shadow" "cat /etc/shadow"

	# --- Overlay state dirs (Linux only) ---
	# Verify overlayStateDir can read existing content
	if [ "$(run_output 'cat $HOME/.test-overlay-dir/original-file')" = "overlay-original" ]; then
		echo "PASS: overlayStateDir can read existing content"
		PASS=$((PASS + 1))
	else
		echo "FAIL: overlayStateDir cannot read existing content"
		FAIL=$((FAIL + 1))
	fi

	# Verify writes work inside the sandbox
	expect_ok "overlayStateDir is writable in sandbox" "echo new-content > \$HOME/.test-overlay-dir/new-file && cat \$HOME/.test-overlay-dir/new-file"

	# Verify writes don't persist to host
	run 'echo modified > $HOME/.test-overlay-dir/original-file'
	if [ "$(cat "$HOME/.test-overlay-dir/original-file")" = "overlay-original" ]; then
		echo "PASS: overlayStateDir writes don't persist to host"
		PASS=$((PASS + 1))
	else
		echo "FAIL: overlayStateDir writes leaked to host"
		FAIL=$((FAIL + 1))
	fi
fi

print_results
exit_status
