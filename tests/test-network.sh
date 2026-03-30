#!/usr/bin/env bash
# Network restriction tests
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS=$(uname)

source "$SCRIPT_DIR/lib.sh"

echo "=== Network restriction tests ($OS) ==="
echo

# --- Backward-compat list-format tests ---

# Build a sandbox with restrictNetwork=true and one allowed domain (list format)
SANDBOXED_NET=$(nix-build --no-out-link "$SCRIPT_DIR/network-allowed.nix")
NET_SHELL="$SANDBOXED_NET/bin/sandboxed-bash-net"
run() { "$NET_SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }


# Test 1: allowed domain works
expect_ok "allowed domain (httpbin.org) reachable" \
	'curl -sf --max-time 10 -o /dev/null http://httpbin.org/get'

# Test 2: blocked domain fails
expect_fail "blocked domain (example.com) denied" \
	'curl -sf --max-time 10 -o /dev/null http://example.com'

# Test 3: unrestricted mode still works
SANDBOXED_UNRES=$(nix-build --no-out-link "$SCRIPT_DIR/network-unrestricted.nix")
UNRES_SHELL="$SANDBOXED_UNRES/bin/sandboxed-bash-unres"
run() { "$UNRES_SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }


expect_ok "unrestricted mode can reach any domain" \
	'curl -s --max-time 10 -o /dev/null http://example.com'

# Test 4: HTTPS with SSL verification works (proves CA injection)
NET_SHELL_2="$SANDBOXED_NET/bin/sandboxed-bash-net"
run() { "$NET_SHELL_2" --norc --noprofile -c "$@" >/dev/null 2>&1; }


expect_ok "HTTPS with SSL verification works (MITM CA injection)" \
	'curl -sf --max-time 10 -o /dev/null https://httpbin.org/get'

# Test 5: empty allowlist blocks everything
SANDBOXED_BLOCK=$(nix-build --no-out-link "$SCRIPT_DIR/network-blocked.nix")
BLOCK_SHELL="$SANDBOXED_BLOCK/bin/sandboxed-bash-block"
run() { "$BLOCK_SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }


expect_fail "empty allowlist blocks all domains" \
	'curl -sf --max-time 10 -o /dev/null http://example.com'

# Test 6 (Linux only): DNS resolution is blocked when restrictNetwork=true
if [ "$OS" = "Linux" ]; then
	run() { "$NET_SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }
	
	expect_fail "DNS resolution blocked when restrictNetwork=true" \
		'getent hosts example.com'
fi

# --- MITM / method filtering tests (attrset format) ---

SANDBOXED_METHODS=$(nix-build --no-out-link "$SCRIPT_DIR/network-method-filtered.nix")
METHOD_SHELL="$SANDBOXED_METHODS/bin/sandboxed-bash-methods"
run() { "$METHOD_SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }


# Test 7: Allowed method succeeds (GET to httpbin.org)
expect_ok "allowed method (GET httpbin.org) succeeds" \
	'curl -sf --max-time 10 -o /dev/null https://httpbin.org/get'

# Test 8: Blocked method returns 403 (POST to httpbin.org)
expect_fail "blocked method (POST httpbin.org) denied" \
	'curl -sf --max-time 10 -X POST -o /dev/null https://httpbin.org/post'

# Test 9: Wildcard method domain allows POST (postman-echo.com)
expect_ok "wildcard method domain allows POST" \
	'curl -sf --max-time 10 -X POST -o /dev/null https://postman-echo.com/post'

# Test 10: URL > 8KB returns 414
LONG_PATH=$(printf 'x%.0s' $(seq 1 8200))
expect_fail "URL > 8KB returns 414" \
	"curl -sf --max-time 10 -o /dev/null \"https://httpbin.org/get?q=$LONG_PATH\""

# Test 11: WebSocket upgrade blocked
expect_fail "WebSocket upgrade blocked" \
	'curl -sf --max-time 10 -o /dev/null -H "Upgrade: websocket" -H "Connection: Upgrade" https://httpbin.org/get'

# --- Direct-to-IP bypass tests (prove kernel-level enforcement) ---

run() { "$NET_SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }


# Test 12: direct IP bypassing proxy is blocked
expect_fail "direct IP bypass blocked (curl --noproxy)" \
	'curl -sf --noproxy "*" --max-time 5 http://1.1.1.1'

# Test 13: raw TCP connection bypassing proxy is blocked
expect_fail "raw TCP bypass blocked (bash /dev/tcp)" \
	'exec 3<>/dev/tcp/1.1.1.1/80'

# Test 14 (Linux only): --connect-to direct IP for allowed domain blocked
if [ "$OS" = "Linux" ]; then
	expect_fail "direct IP for allowed domain blocked (--connect-to)" \
		'curl -sf --max-time 5 --connect-to ::1.1.1.1: http://httpbin.org/get'
fi

print_results
exit_status
