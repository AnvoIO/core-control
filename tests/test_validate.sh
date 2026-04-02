#!/bin/bash
set -euo pipefail

# =============================================================================
# core-control — Inventory Validation Tests
# =============================================================================
# Tests validate.sh against valid and invalid inventory files.
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

VALIDATE="${PROJECT_DIR}/scripts/inventory/validate.sh"

echo ""
echo "========================================="
echo "  Inventory Validation Tests"
echo "========================================="
echo ""

# -------------------------------------------------------------------------
# Test: Valid minimal inventory (producers)
# -------------------------------------------------------------------------
echo "--- Valid Inventories ---"

cat > "${WORK_DIR}/valid_minimal.inv" <<'INV'
# Test inventory
libre-testnet-potato1|testnet|producer|10.10.10.181|8881|9871||potato1|PUB_K1_xxx=KEY:PVT_K1_xxx
INV

if "$VALIDATE" "${WORK_DIR}/valid_minimal.inv" >/dev/null 2>&1; then
    pass "Valid minimal producer inventory"
else
    fail "Valid minimal producer inventory rejected"
fi

# -------------------------------------------------------------------------
# Test: Valid multi-node inventory
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/valid_multi.inv" <<'INV'
libre-testnet-potato1|testnet|producer|10.10.10.181|8881|9871||potato1|PUB_K1_aaa=KEY:PVT_K1_aaa
libre-testnet-potato2|testnet|producer|10.10.10.181|8882|9872||potato2|PUB_K1_bbb=KEY:PVT_K1_bbb
libre-mainnet-crypto|mainnet|producer|10.10.10.182|8880|9870||cryptobloks|PUB_K1_ccc=KEY:PVT_K1_ccc
INV

if "$VALIDATE" "${WORK_DIR}/valid_multi.inv" >/dev/null 2>&1; then
    pass "Valid multi-node inventory (3 nodes, 2 networks)"
else
    fail "Valid multi-node inventory rejected"
fi

# -------------------------------------------------------------------------
# Test: Valid inventory with optional fields
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/valid_optional.inv" <<'INV'
libre-testnet-p1|testnet|producer|10.10.10.181|8881|9871||p1|PUB_K1_xxx=KEY:PVT_K1_xxx|production|50000|5|20|200000
INV

if "$VALIDATE" "${WORK_DIR}/valid_optional.inv" >/dev/null 2>&1; then
    pass "Valid inventory with all optional fields"
else
    fail "Valid inventory with optional fields rejected"
fi

# -------------------------------------------------------------------------
# Test: Valid inventory with comments and blank lines
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/valid_comments.inv" <<'INV'
# This is a comment
# Another comment

libre-testnet-p1|testnet|producer|10.10.10.181|8881|9871||p1|PUB_K1_xxx=KEY:PVT_K1_xxx

# More comments between entries
libre-testnet-p2|testnet|producer|10.10.10.181|8882|9872||p2|PUB_K1_yyy=KEY:PVT_K1_yyy
INV

if "$VALIDATE" "${WORK_DIR}/valid_comments.inv" >/dev/null 2>&1; then
    pass "Valid inventory with comments and blank lines"
else
    fail "Valid inventory with comments and blank lines rejected"
fi

# -------------------------------------------------------------------------
# Test: Valid seed node (no HTTP port needed)
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/valid_seed.inv" <<'INV'
libre-testnet-seed1|testnet|seed|10.10.10.181||9871|||
INV

if "$VALIDATE" "${WORK_DIR}/valid_seed.inv" >/dev/null 2>&1; then
    pass "Valid seed node (empty HTTP port)"
else
    fail "Valid seed node rejected"
fi

# -------------------------------------------------------------------------
# Test: Valid non-producer roles
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/valid_roles.inv" <<'INV'
libre-testnet-api|testnet|light-api|10.10.10.181|8881|9871|||
libre-testnet-full|testnet|full-api|10.10.10.181|8882|9872|||
libre-testnet-hist|testnet|full-history|10.10.10.181|8883|9873|||
INV

if "$VALIDATE" "${WORK_DIR}/valid_roles.inv" >/dev/null 2>&1; then
    pass "Valid non-producer roles (light-api, full-api, full-history)"
else
    fail "Valid non-producer roles rejected"
fi

echo ""
echo "--- Invalid Inventories ---"

# -------------------------------------------------------------------------
# Test: Too few fields
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_few_fields.inv" <<'INV'
libre-testnet-p1|testnet|producer|10.10.10.181|8881
INV

if "$VALIDATE" "${WORK_DIR}/invalid_few_fields.inv" >/dev/null 2>&1; then
    fail "Should reject: too few fields"
else
    pass "Rejects too few fields"
fi

# -------------------------------------------------------------------------
# Test: Invalid network
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_network.inv" <<'INV'
libre-devnet-p1|devnet|producer|10.10.10.181|8881|9871||p1|PUB_K1_xxx=KEY:PVT_K1_xxx
INV

if "$VALIDATE" "${WORK_DIR}/invalid_network.inv" >/dev/null 2>&1; then
    fail "Should reject: invalid network 'devnet'"
else
    pass "Rejects invalid network"
fi

# -------------------------------------------------------------------------
# Test: Invalid role
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_role.inv" <<'INV'
libre-testnet-p1|testnet|validator|10.10.10.181|8881|9871|p1|PUB_K1_xxx=KEY:PVT_K1_xxx
INV

if "$VALIDATE" "${WORK_DIR}/invalid_role.inv" >/dev/null 2>&1; then
    fail "Should reject: invalid role 'validator'"
else
    pass "Rejects invalid role"
fi

# -------------------------------------------------------------------------
# Test: Invalid IP address
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_ip.inv" <<'INV'
libre-testnet-p1|testnet|producer|999.999.999.999|8881|9871||p1|PUB_K1_xxx=KEY:PVT_K1_xxx
INV

if "$VALIDATE" "${WORK_DIR}/invalid_ip.inv" >/dev/null 2>&1; then
    fail "Should reject: invalid IP 999.999.999.999"
else
    pass "Rejects invalid IP address"
fi

# -------------------------------------------------------------------------
# Test: Invalid port (out of range)
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_port.inv" <<'INV'
libre-testnet-p1|testnet|producer|10.10.10.181|99999|9871||p1|PUB_K1_xxx=KEY:PVT_K1_xxx
INV

if "$VALIDATE" "${WORK_DIR}/invalid_port.inv" >/dev/null 2>&1; then
    fail "Should reject: port 99999 out of range"
else
    pass "Rejects out-of-range port"
fi

# -------------------------------------------------------------------------
# Test: Invalid port (non-numeric)
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_port_nan.inv" <<'INV'
libre-testnet-p1|testnet|producer|10.10.10.181|abc|9871||p1|PUB_K1_xxx=KEY:PVT_K1_xxx
INV

if "$VALIDATE" "${WORK_DIR}/invalid_port_nan.inv" >/dev/null 2>&1; then
    fail "Should reject: non-numeric port 'abc'"
else
    pass "Rejects non-numeric port"
fi

# -------------------------------------------------------------------------
# Test: Duplicate container names
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_dup_name.inv" <<'INV'
libre-testnet-p1|testnet|producer|10.10.10.181|8881|9871||p1|PUB_K1_aaa=KEY:PVT_K1_aaa
libre-testnet-p1|testnet|producer|10.10.10.181|8882|9872||p2|PUB_K1_bbb=KEY:PVT_K1_bbb
INV

if "$VALIDATE" "${WORK_DIR}/invalid_dup_name.inv" >/dev/null 2>&1; then
    fail "Should reject: duplicate container name"
else
    pass "Rejects duplicate container names"
fi

# -------------------------------------------------------------------------
# Test: Port conflict on same bind IP (HTTP)
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_port_conflict_http.inv" <<'INV'
libre-testnet-p1|testnet|producer|10.10.10.181|8881|9871||p1|PUB_K1_aaa=KEY:PVT_K1_aaa
libre-testnet-p2|testnet|producer|10.10.10.181|8881|9872||p2|PUB_K1_bbb=KEY:PVT_K1_bbb
INV

if "$VALIDATE" "${WORK_DIR}/invalid_port_conflict_http.inv" >/dev/null 2>&1; then
    fail "Should reject: HTTP port conflict on same IP"
else
    pass "Rejects HTTP port conflict on same bind IP"
fi

# -------------------------------------------------------------------------
# Test: Port conflict on same bind IP (P2P)
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_port_conflict_p2p.inv" <<'INV'
libre-testnet-p1|testnet|producer|10.10.10.181|8881|9871||p1|PUB_K1_aaa=KEY:PVT_K1_aaa
libre-testnet-p2|testnet|producer|10.10.10.181|8882|9871||p2|PUB_K1_bbb=KEY:PVT_K1_bbb
INV

if "$VALIDATE" "${WORK_DIR}/invalid_port_conflict_p2p.inv" >/dev/null 2>&1; then
    fail "Should reject: P2P port conflict on same IP"
else
    pass "Rejects P2P port conflict on same bind IP"
fi

# -------------------------------------------------------------------------
# Test: Cross-type port conflict (HTTP vs P2P on same IP)
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_port_cross.inv" <<'INV'
libre-testnet-p1|testnet|producer|10.10.10.181|8881|9871||p1|PUB_K1_aaa=KEY:PVT_K1_aaa
libre-testnet-p2|testnet|producer|10.10.10.181|9871|9872||p2|PUB_K1_bbb=KEY:PVT_K1_bbb
INV

if "$VALIDATE" "${WORK_DIR}/invalid_port_cross.inv" >/dev/null 2>&1; then
    fail "Should reject: HTTP port 9871 conflicts with P2P port 9871 on same IP"
else
    pass "Rejects cross-type port conflict (HTTP vs P2P)"
fi

# -------------------------------------------------------------------------
# Test: Same ports on DIFFERENT IPs should be OK
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/valid_same_port_diff_ip.inv" <<'INV'
libre-testnet-p1|testnet|producer|10.10.10.181|8880|9870||p1|PUB_K1_aaa=KEY:PVT_K1_aaa
libre-mainnet-p1|mainnet|producer|10.10.10.182|8880|9870||p1m|PUB_K1_bbb=KEY:PVT_K1_bbb
INV

if "$VALIDATE" "${WORK_DIR}/valid_same_port_diff_ip.inv" >/dev/null 2>&1; then
    pass "Allows same ports on different bind IPs"
else
    fail "Wrongly rejects same ports on different bind IPs"
fi

# -------------------------------------------------------------------------
# Test: Producer missing producer name
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_no_producer_name.inv" <<'INV'
libre-testnet-p1|testnet|producer|10.10.10.181|8881|9871|||PUB_K1_xxx=KEY:PVT_K1_xxx
INV

if "$VALIDATE" "${WORK_DIR}/invalid_no_producer_name.inv" >/dev/null 2>&1; then
    fail "Should reject: producer role without PRODUCER_NAME"
else
    pass "Rejects producer role without producer name"
fi

# -------------------------------------------------------------------------
# Test: Producer missing signature provider
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_no_sig.inv" <<'INV'
libre-testnet-p1|testnet|producer|10.10.10.181|8881|9871||p1|
INV

if "$VALIDATE" "${WORK_DIR}/invalid_no_sig.inv" >/dev/null 2>&1; then
    fail "Should reject: producer role without SIGNATURE_PROVIDER"
else
    pass "Rejects producer role without signature provider"
fi

# -------------------------------------------------------------------------
# Test: Invalid container name (starts with hyphen)
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/invalid_name.inv" <<'INV'
-bad-name|testnet|producer|10.10.10.181|8881|9871||p1|PUB_K1_xxx=KEY:PVT_K1_xxx
INV

if "$VALIDATE" "${WORK_DIR}/invalid_name.inv" >/dev/null 2>&1; then
    fail "Should reject: container name starting with hyphen"
else
    pass "Rejects invalid container name"
fi

# -------------------------------------------------------------------------
# Test: Empty file (should pass — no nodes defined)
# -------------------------------------------------------------------------
cat > "${WORK_DIR}/valid_empty.inv" <<'INV'
# Just comments, no nodes
#
INV

if "$VALIDATE" "${WORK_DIR}/valid_empty.inv" >/dev/null 2>&1; then
    pass "Accepts empty inventory (comments only)"
else
    fail "Rejects empty inventory"
fi

# -------------------------------------------------------------------------
# Test: No arguments
# -------------------------------------------------------------------------
if "$VALIDATE" >/dev/null 2>&1; then
    fail "Should reject: no arguments"
else
    pass "Rejects missing argument"
fi

# -------------------------------------------------------------------------
# Test: Non-existent file
# -------------------------------------------------------------------------
if "$VALIDATE" "/tmp/does_not_exist_$$" >/dev/null 2>&1; then
    fail "Should reject: non-existent file"
else
    pass "Rejects non-existent file"
fi

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "========================================="
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}All validation tests passed${NC}"
else
    echo -e "${RED}${FAILURES} test(s) failed${NC}"
fi
echo "========================================="
exit "$FAILURES"
