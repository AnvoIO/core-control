#!/bin/bash
set -euo pipefail

# =============================================================================
# core-control — Inventory Import/Export Integration Tests
# =============================================================================
# Tests the full import → node.conf → generate-config → export round-trip.
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
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Source cc-common to get paths and RECOMMENDED_CORE_VERSION
# Note: CC_DIR is set by cc-common.sh. PROJECT_DIR gets overwritten by
# core-node's common.sh, so we use CC_DIR after this point.
source "${PROJECT_DIR}/scripts/lib/cc-common.sh"

# For test isolation, we create a temporary core-control.conf that points
# NODES_DIR and DATA_ROOT to our temp workspace. We do this by creating a
# wrapper directory structure that cc-common.sh can follow.
TEST_CC_DIR="${WORK_DIR}/cc"
mkdir -p "${TEST_CC_DIR}/nodes" "${TEST_CC_DIR}/inventory"
mkdir -p "${WORK_DIR}/data/libre/mainnet" "${WORK_DIR}/data/libre/testnet"

# Write a test core-control.conf
cat > "${TEST_CC_DIR}/core-control.conf" <<CONF
CORE_NODE_DIR=${CORE_NODE_DIR}
DATA_ROOT=${WORK_DIR}/data
SSH_PORT=22
CONF

# Symlink scripts directory so cc-common.sh can find it
ln -s "${CC_DIR}/scripts" "${TEST_CC_DIR}/scripts"

# Override NODES_DIR and DATA_ROOT for this test's sourced context
NODES_DIR="${TEST_CC_DIR}/nodes"
DATA_ROOT="${WORK_DIR}/data"

# Create wrapper scripts that source from our test CC_DIR
run_import() {
    # We need import.sh to use our test config. The cleanest way is to
    # temporarily swap core-control.conf, run import, then restore it.
    local orig_conf="${CC_DIR}/core-control.conf"
    local backup_conf="${WORK_DIR}/core-control.conf.bak"
    cp "$orig_conf" "$backup_conf"
    cp "${TEST_CC_DIR}/core-control.conf" "$orig_conf"
    # Also need NODES_DIR to point to our test dir — but cc-common.sh
    # derives it from CC_DIR. Since CC_DIR = PROJECT_DIR, nodes/ is
    # PROJECT_DIR/nodes/. We need to symlink.
    local orig_nodes="${CC_DIR}/nodes"
    local orig_nodes_bak="${WORK_DIR}/nodes_orig"
    if [[ -e "$orig_nodes" ]]; then
        mv "$orig_nodes" "$orig_nodes_bak"
    fi
    ln -sfn "${TEST_CC_DIR}/nodes" "$orig_nodes"

    "$@"
    local rc=$?

    # Restore
    cp "$backup_conf" "$orig_conf"
    rm -f "$orig_nodes"
    if [[ -e "$orig_nodes_bak" ]]; then
        mv "$orig_nodes_bak" "$orig_nodes"
    else
        mkdir -p "$orig_nodes"
    fi
    return $rc
}

IMPORT="${CC_DIR}/scripts/inventory/import.sh"
EXPORT="${CC_DIR}/scripts/inventory/export.sh"

echo ""
echo "========================================="
echo "  Inventory Import/Export Integration"
echo "========================================="
echo ""

# -------------------------------------------------------------------------
# Create test inventory
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/test.inv" <<'INV'
# Test inventory for integration tests
test-node-alpha|testnet|producer|10.10.10.181|8881|9871||alpha|PUB_K1_aaa=KEY:PVT_K1_aaa|standard|50000|5
test-node-beta|testnet|producer|10.10.10.181|8882|9872||beta|PUB_K1_bbb=KEY:PVT_K1_bbb|production|100000|10
test-node-gamma|mainnet|producer|10.10.10.182|8880|9870||gamma|PUB_K1_ccc=KEY:PVT_K1_ccc
INV

# -------------------------------------------------------------------------
# Test: Import creates node directories
# -------------------------------------------------------------------------
echo "--- Import ---"

info "Running import (skip-firewall, since no ufw in test env)..."
if run_import "$IMPORT" "${WORK_DIR}/test.inv" --skip-firewall >/dev/null 2>&1; then
    pass "import.sh exits successfully"
else
    fail "import.sh exited with error"
fi

# Check node directories were created
for node_name in test-node-alpha test-node-beta test-node-gamma; do
    if [[ -f "${TEST_CC_DIR}/nodes/${node_name}/node.conf" ]]; then
        pass "Import created ${node_name}/node.conf"
    else
        fail "Import did not create ${node_name}/node.conf"
    fi
done

# -------------------------------------------------------------------------
# Test: Imported node.conf has correct values
# -------------------------------------------------------------------------
echo ""
echo "--- Imported Config Verification ---"

check_imported_value() {
    local node="$1" key="$2" expected="$3"
    local conf="${TEST_CC_DIR}/nodes/${node}/node.conf"
    local actual
    actual="$(grep "^${key}=" "$conf" 2>/dev/null | tail -1 | cut -d= -f2-)"
    if [[ "$actual" == "$expected" ]]; then
        pass "${node}: ${key}=${expected}"
    else
        fail "${node}: ${key}='${actual}', expected '${expected}'"
    fi
}

check_imported_value "test-node-alpha" "CONTAINER_NAME" "test-node-alpha"
check_imported_value "test-node-alpha" "NETWORK" "testnet"
check_imported_value "test-node-alpha" "NODE_ROLE" "producer"
check_imported_value "test-node-alpha" "BIND_IP" "10.10.10.181"
check_imported_value "test-node-alpha" "HTTP_PORT" "8881"
check_imported_value "test-node-alpha" "P2P_PORT" "9871"
check_imported_value "test-node-alpha" "PRODUCER_NAME" "alpha"
check_imported_value "test-node-alpha" "SIGNATURE_PROVIDER" "PUB_K1_aaa=KEY:PVT_K1_aaa"
check_imported_value "test-node-alpha" "LOG_PROFILE" "standard"
check_imported_value "test-node-alpha" "SNAPSHOT_INTERVAL" "50000"
check_imported_value "test-node-alpha" "SNAPSHOT_RETENTION" "5"

# Beta has different log profile
check_imported_value "test-node-beta" "LOG_PROFILE" "production"
check_imported_value "test-node-beta" "SNAPSHOT_INTERVAL" "100000"

# Gamma defaulted optional fields
check_imported_value "test-node-gamma" "NETWORK" "mainnet"
check_imported_value "test-node-gamma" "BIND_IP" "10.10.10.182"
check_imported_value "test-node-gamma" "LOG_PROFILE" "standard"

# -------------------------------------------------------------------------
# Test: Auto-derived values are present
# -------------------------------------------------------------------------
echo ""
echo "--- Auto-Derived Values ---"

alpha_conf="${TEST_CC_DIR}/nodes/test-node-alpha/node.conf"

# CORE_VERSION should match RECOMMENDED_CORE_VERSION
alpha_version="$(grep "^CORE_VERSION=" "$alpha_conf" | cut -d= -f2-)"
if [[ "$alpha_version" == "$RECOMMENDED_CORE_VERSION" ]]; then
    pass "CORE_VERSION=${alpha_version} matches RECOMMENDED_CORE_VERSION"
else
    fail "CORE_VERSION='${alpha_version}', expected '${RECOMMENDED_CORE_VERSION}'"
fi

# STORAGE_PATH should be derived from DATA_ROOT + network + producer_name
alpha_storage="$(grep "^STORAGE_PATH=" "$alpha_conf" | cut -d= -f2-)"
if [[ "$alpha_storage" == "${DATA_ROOT}/libre/testnet/alpha" ]]; then
    pass "STORAGE_PATH correctly derived: ${alpha_storage}"
else
    fail "STORAGE_PATH='${alpha_storage}', expected '${DATA_ROOT}/libre/testnet/alpha'"
fi

# STATE_IN_MEMORY should be true
check_imported_value "test-node-alpha" "STATE_IN_MEMORY" "true"

# Resource defaults should be populated
for key in CHAIN_STATE_DB_SIZE CHAIN_THREADS HTTP_THREADS NET_THREADS MAX_CLIENTS MAX_TRANSACTION_TIME; do
    if grep -q "^${key}=" "$alpha_conf"; then
        pass "Resource default set: ${key}"
    else
        fail "Resource default missing: ${key}"
    fi
done

# PEERS should be populated (from core-node's peers-testnet.conf)
alpha_peers="$(grep "^PEERS=" "$alpha_conf" | cut -d= -f2-)"
if [[ -n "$alpha_peers" ]]; then
    pass "PEERS populated from core-node peers file"
else
    fail "PEERS not populated"
fi

# -------------------------------------------------------------------------
# Test: generate-config.sh ran and created runtime files
# -------------------------------------------------------------------------
echo ""
echo "--- Generated Runtime Files ---"

for node_name in test-node-alpha test-node-beta test-node-gamma; do
    node_conf="${TEST_CC_DIR}/nodes/${node_name}/node.conf"
    storage="$(grep "^STORAGE_PATH=" "$node_conf" | cut -d= -f2-)"

    for gen_file in config.ini docker-compose.yml genesis.json logging.json node.conf; do
        if [[ -f "${storage}/config/${gen_file}" ]]; then
            pass "${node_name}: ${gen_file} generated"
        else
            fail "${node_name}: ${gen_file} NOT generated at ${storage}/config/"
        fi
    done
done

# -------------------------------------------------------------------------
# Test: Generated config.ini has correct content
# -------------------------------------------------------------------------
echo ""
echo "--- config.ini Content Verification ---"

alpha_ini="${DATA_ROOT}/libre/testnet/alpha/config/config.ini"
if [[ -f "$alpha_ini" ]]; then
    # Check bind IP and port
    if grep -q "http-server-address = 10.10.10.181:8881" "$alpha_ini"; then
        pass "config.ini: HTTP address correct"
    else
        fail "config.ini: HTTP address incorrect"
    fi

    if grep -q "p2p-listen-endpoint = 10.10.10.181:9871" "$alpha_ini"; then
        pass "config.ini: P2P endpoint correct"
    else
        fail "config.ini: P2P endpoint incorrect"
    fi

    # Producer plugin should be present
    if grep -q "core_net::producer_plugin" "$alpha_ini"; then
        pass "config.ini: producer_plugin present"
    else
        fail "config.ini: producer_plugin missing"
    fi

    # Producer name should be set
    if grep -q "producer-name = alpha" "$alpha_ini"; then
        pass "config.ini: producer-name correct"
    else
        fail "config.ini: producer-name incorrect"
    fi

    # No unresolved placeholders
    if grep -v '^#' "$alpha_ini" | grep -q '{{[A-Z_]*}}'; then
        fail "config.ini: unresolved placeholders found"
    else
        pass "config.ini: no unresolved placeholders"
    fi
else
    fail "config.ini not found at ${alpha_ini}"
fi

# -------------------------------------------------------------------------
# Test: Import is idempotent (skips existing nodes)
# -------------------------------------------------------------------------
echo ""
echo "--- Idempotency ---"

import_output="$(run_import "$IMPORT" "${WORK_DIR}/test.inv" --skip-firewall 2>&1)"
if echo "$import_output" | grep -q "already exists"; then
    pass "Re-import skips existing nodes"
else
    fail "Re-import did not detect existing nodes"
fi

if echo "$import_output" | grep -q "Skipped:  3"; then
    pass "Re-import reports 3 skipped"
else
    fail "Re-import skip count incorrect"
fi

# -------------------------------------------------------------------------
# Test: Export round-trip
# -------------------------------------------------------------------------
echo ""
echo "--- Export ---"

export_file="${WORK_DIR}/exported.inv"
run_import "$EXPORT" "$export_file" >/dev/null 2>&1

if [[ -f "$export_file" ]]; then
    pass "export.sh creates output file"
else
    fail "export.sh did not create output file"
    exit "$FAILURES"
fi

# Count exported data lines (non-comment, non-blank)
export_count="$(grep -cv '^\s*#\|^\s*$' "$export_file" 2>/dev/null || echo 0)"
if [[ "$export_count" -eq 3 ]]; then
    pass "Export contains 3 node entries"
else
    fail "Export contains ${export_count} entries, expected 3"
fi

# Verify key fields survive round-trip
if grep -q "test-node-alpha|testnet|producer|10.10.10.181|8881|9871||alpha|" "$export_file"; then
    pass "Export preserves alpha node fields"
else
    fail "Export alpha node fields incorrect"
fi

if grep -q "test-node-gamma|mainnet|producer|10.10.10.182|8880|9870||gamma|" "$export_file"; then
    pass "Export preserves gamma node fields"
else
    fail "Export gamma node fields incorrect"
fi

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "========================================="
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}All inventory integration tests passed${NC}"
else
    echo -e "${RED}${FAILURES} test(s) failed${NC}"
fi
echo "========================================="
exit "$FAILURES"
