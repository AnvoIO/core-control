#!/bin/bash
set -euo pipefail

# =============================================================================
# core-control — cc-common.sh Unit Tests
# =============================================================================
# Tests inventory helpers: list_all_nodes, get_node_value, get_node_conf,
# node_count, create_node_conf, write_node_config, load_peers.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAILURES=$((FAILURES + 1)); }
info() { echo -e "  ${YELLOW}INFO${NC} $1"; }

FAILURES=0

# ---------------------------------------------------------------------------
# Setup: create a temporary NODES_DIR with fake nodes
# Override NODES_DIR and INVENTORY_DIR before sourcing cc-common.sh
# ---------------------------------------------------------------------------
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Create fake nodes directory structure
FAKE_NODES_DIR="${WORK_DIR}/nodes"
mkdir -p "${FAKE_NODES_DIR}/libre-testnet-potato1"
mkdir -p "${FAKE_NODES_DIR}/libre-testnet-potato2"
mkdir -p "${FAKE_NODES_DIR}/libre-mainnet-crypto"
mkdir -p "${FAKE_NODES_DIR}/empty-dir-no-conf"

cat > "${FAKE_NODES_DIR}/libre-testnet-potato1/node.conf" <<'CONF'
CONTAINER_NAME=libre-testnet-potato1
NETWORK=testnet
NODE_ROLE=producer
BIND_IP=10.10.10.181
HTTP_PORT=8881
P2P_PORT=9871
PRODUCER_NAME=potato1
STORAGE_PATH=/data/libre/testnet/potato1
CONF

cat > "${FAKE_NODES_DIR}/libre-testnet-potato2/node.conf" <<'CONF'
CONTAINER_NAME=libre-testnet-potato2
NETWORK=testnet
NODE_ROLE=producer
BIND_IP=10.10.10.181
HTTP_PORT=8882
P2P_PORT=9872
PRODUCER_NAME=potato2
STORAGE_PATH=/data/libre/testnet/potato2
CONF

cat > "${FAKE_NODES_DIR}/libre-mainnet-crypto/node.conf" <<'CONF'
CONTAINER_NAME=libre-mainnet-crypto
NETWORK=mainnet
NODE_ROLE=producer
BIND_IP=10.10.10.182
HTTP_PORT=8880
P2P_PORT=9870
PRODUCER_NAME=cryptobloks
STORAGE_PATH=/data/libre/mainnet/cryptobloks
CONF

# Source cc-common.sh — it will load core-control.conf and core-node libs
source "${PROJECT_DIR}/scripts/lib/cc-common.sh"

# Override NODES_DIR to our test directory
NODES_DIR="$FAKE_NODES_DIR"

echo ""
echo "========================================="
echo "  cc-common.sh Unit Tests"
echo "========================================="
echo ""

# -------------------------------------------------------------------------
# Test: list_all_nodes
# -------------------------------------------------------------------------
echo "--- list_all_nodes ---"

nodes_output="$(list_all_nodes)"
node_lines="$(echo "$nodes_output" | wc -l)"

if [[ "$node_lines" -eq 3 ]]; then
    pass "list_all_nodes returns 3 nodes (skips dir without node.conf)"
else
    fail "list_all_nodes returned ${node_lines} nodes, expected 3"
fi

# Check sorted order
first_node="$(echo "$nodes_output" | head -1)"
if [[ "$first_node" == "libre-mainnet-crypto" ]]; then
    pass "list_all_nodes output is sorted alphabetically"
else
    fail "list_all_nodes not sorted: first was '${first_node}', expected 'libre-mainnet-crypto'"
fi

# Verify empty-dir-no-conf is excluded
if echo "$nodes_output" | grep -q "empty-dir-no-conf"; then
    fail "list_all_nodes should skip directories without node.conf"
else
    pass "list_all_nodes skips directories without node.conf"
fi

# -------------------------------------------------------------------------
# Test: node_count
# -------------------------------------------------------------------------
echo ""
echo "--- node_count ---"

count="$(node_count)"
if [[ "$count" -eq 3 ]]; then
    pass "node_count returns 3"
else
    fail "node_count returned ${count}, expected 3"
fi

# -------------------------------------------------------------------------
# Test: get_node_conf
# -------------------------------------------------------------------------
echo ""
echo "--- get_node_conf ---"

conf_path="$(get_node_conf "libre-testnet-potato1")"
if [[ "$conf_path" == "${FAKE_NODES_DIR}/libre-testnet-potato1/node.conf" ]]; then
    pass "get_node_conf returns correct path"
else
    fail "get_node_conf returned '${conf_path}'"
fi

# Non-existent node
if get_node_conf "nonexistent" >/dev/null 2>&1; then
    fail "get_node_conf should fail for nonexistent node"
else
    pass "get_node_conf fails for nonexistent node"
fi

# -------------------------------------------------------------------------
# Test: get_node_value
# -------------------------------------------------------------------------
echo ""
echo "--- get_node_value ---"

val="$(get_node_value "libre-testnet-potato1" "NETWORK" "?")"
if [[ "$val" == "testnet" ]]; then
    pass "get_node_value reads NETWORK=testnet"
else
    fail "get_node_value NETWORK returned '${val}', expected 'testnet'"
fi

val="$(get_node_value "libre-testnet-potato1" "HTTP_PORT" "?")"
if [[ "$val" == "8881" ]]; then
    pass "get_node_value reads HTTP_PORT=8881"
else
    fail "get_node_value HTTP_PORT returned '${val}', expected '8881'"
fi

val="$(get_node_value "libre-testnet-potato1" "NONEXISTENT_KEY" "default_val")"
if [[ "$val" == "default_val" ]]; then
    pass "get_node_value returns default for missing key"
else
    fail "get_node_value missing key returned '${val}', expected 'default_val'"
fi

val="$(get_node_value "nonexistent-node" "NETWORK" "fallback")"
if [[ "$val" == "fallback" ]]; then
    pass "get_node_value returns default for nonexistent node"
else
    fail "get_node_value nonexistent node returned '${val}', expected 'fallback'"
fi

# -------------------------------------------------------------------------
# Test: get_all_node_statuses
# -------------------------------------------------------------------------
echo ""
echo "--- get_all_node_statuses ---"

statuses="$(get_all_node_statuses)"
status_lines="$(echo "$statuses" | wc -l)"

if [[ "$status_lines" -eq 3 ]]; then
    pass "get_all_node_statuses returns 3 entries"
else
    fail "get_all_node_statuses returned ${status_lines} entries, expected 3"
fi

# Verify format: NAME|STATUS|NETWORK|ROLE|BIND_IP|HTTP_PORT
first_status="$(echo "$statuses" | head -1)"
field_count="$(echo "$first_status" | awk -F'|' '{print NF}')"
if [[ "$field_count" -eq 6 ]]; then
    pass "get_all_node_statuses output has 6 pipe-delimited fields"
else
    fail "get_all_node_statuses field count: ${field_count}, expected 6"
fi

# All should be STOPPED (no docker running in test env)
if echo "$statuses" | grep -q "RUNNING"; then
    info "Some nodes show RUNNING (docker may be running containers with matching names)"
else
    pass "All nodes show STOPPED status (expected in test environment)"
fi

# -------------------------------------------------------------------------
# Test: create_node_conf
# -------------------------------------------------------------------------
echo ""
echo "--- create_node_conf ---"

new_conf="$(create_node_conf "test-new-node")"
if [[ -f "$new_conf" ]]; then
    pass "create_node_conf creates file at ${new_conf}"
else
    fail "create_node_conf did not create file"
fi

if [[ -d "${FAKE_NODES_DIR}/test-new-node" ]]; then
    pass "create_node_conf creates node directory"
else
    fail "create_node_conf did not create directory"
fi

# Verify it's a valid config file (has header comment)
if head -1 "$new_conf" | grep -q "^#"; then
    pass "create_node_conf creates file with header comment"
else
    fail "create_node_conf file missing header"
fi

# -------------------------------------------------------------------------
# Test: write_node_config
# -------------------------------------------------------------------------
echo ""
echo "--- write_node_config ---"

# create_node_conf already set CONFIG_FILE to the new node's conf
# Now populate it
write_node_config \
    "test-new-node" \
    "testnet" \
    "producer" \
    "10.10.10.181" \
    "8888" \
    "9876" \
    "" \
    "/data/libre/testnet/test-new-node" \
    "standard" \
    "100000" \
    "10" \
    "100000" \
    "10" \
    "testprod" \
    "PUB_K1_test=KEY:PVT_K1_test"

# Verify key fields were written
check_conf_value() {
    local key="$1" expected="$2"
    local actual
    actual="$(grep "^${key}=" "$new_conf" 2>/dev/null | tail -1 | cut -d= -f2-)"
    if [[ "$actual" == "$expected" ]]; then
        pass "write_node_config: ${key}=${expected}"
    else
        fail "write_node_config: ${key}='${actual}', expected '${expected}'"
    fi
}

check_conf_value "CONTAINER_NAME" "test-new-node"
check_conf_value "NETWORK" "testnet"
check_conf_value "NODE_ROLE" "producer"
check_conf_value "BIND_IP" "10.10.10.181"
check_conf_value "HTTP_PORT" "8888"
check_conf_value "P2P_PORT" "9876"
check_conf_value "STORAGE_PATH" "/data/libre/testnet/test-new-node"
check_conf_value "STATE_IN_MEMORY" "true"
check_conf_value "LOG_PROFILE" "standard"
check_conf_value "PRODUCER_NAME" "testprod"
check_conf_value "SIGNATURE_PROVIDER" "PUB_K1_test=KEY:PVT_K1_test"
check_conf_value "RESTART_POLICY" "unless-stopped"
check_conf_value "API_GATEWAY_ENABLED" "false"
check_conf_value "FIREWALL_ENABLED" "true"

# Verify resource defaults were applied (producer role)
if grep -q "^CHAIN_STATE_DB_SIZE=" "$new_conf"; then
    pass "write_node_config: CHAIN_STATE_DB_SIZE set"
else
    fail "write_node_config: CHAIN_STATE_DB_SIZE missing"
fi

if grep -q "^CHAIN_THREADS=" "$new_conf"; then
    pass "write_node_config: CHAIN_THREADS set"
else
    fail "write_node_config: CHAIN_THREADS missing"
fi

# Verify CORE_VERSION is set from RECOMMENDED_CORE_VERSION
core_ver="$(grep "^CORE_VERSION=" "$new_conf" | cut -d= -f2-)"
if [[ -n "$core_ver" ]]; then
    pass "write_node_config: CORE_VERSION=${core_ver}"
else
    fail "write_node_config: CORE_VERSION not set"
fi

# -------------------------------------------------------------------------
# Test: write_node_config for non-producer (should NOT write PRODUCER_NAME)
# -------------------------------------------------------------------------
echo ""
echo "--- write_node_config (non-producer) ---"

api_conf="$(create_node_conf "test-api-node")"
write_node_config \
    "test-api-node" \
    "mainnet" \
    "light-api" \
    "0.0.0.0" \
    "9888" \
    "9876" \
    "9080" \
    "/data/libre/mainnet/test-api-node" \
    "production" \
    "100000" \
    "10" \
    "100000" \
    "10" \
    "" \
    ""

if grep -q "^PRODUCER_NAME=" "$api_conf"; then
    fail "write_node_config: PRODUCER_NAME should not be set for light-api"
else
    pass "write_node_config: PRODUCER_NAME correctly absent for light-api"
fi

api_role="$(grep "^NODE_ROLE=" "$api_conf" | cut -d= -f2-)"
if [[ "$api_role" == "light-api" ]]; then
    pass "write_node_config: NODE_ROLE=light-api"
else
    fail "write_node_config: NODE_ROLE='${api_role}', expected 'light-api'"
fi

# -------------------------------------------------------------------------
# Test: load_peers
# -------------------------------------------------------------------------
echo ""
echo "--- load_peers ---"

testnet_peers="$(load_peers "testnet")"
if [[ -n "$testnet_peers" ]]; then
    pass "load_peers testnet returns non-empty: ${testnet_peers:0:60}..."
else
    fail "load_peers testnet returned empty"
fi

# Check comma-separated format
if echo "$testnet_peers" | grep -q ","; then
    pass "load_peers returns comma-separated list"
else
    # Might only have one peer — check if it looks like host:port
    if echo "$testnet_peers" | grep -qE ":[0-9]+$"; then
        pass "load_peers returns single peer in host:port format"
    else
        fail "load_peers format unexpected: ${testnet_peers}"
    fi
fi

mainnet_peers="$(load_peers "mainnet")"
if [[ -n "$mainnet_peers" ]]; then
    pass "load_peers mainnet returns non-empty"
else
    fail "load_peers mainnet returned empty"
fi

# Invalid network should return empty with a warning
invalid_peers="$(load_peers "invalidnet" 2>/dev/null)"
if [[ -z "$invalid_peers" ]]; then
    pass "load_peers returns empty for unknown network"
else
    fail "load_peers should return empty for unknown network, got '${invalid_peers}'"
fi

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "========================================="
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}All cc-common.sh tests passed${NC}"
else
    echo -e "${RED}${FAILURES} test(s) failed${NC}"
fi
echo "========================================="
exit "$FAILURES"
