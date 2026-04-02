#!/bin/bash

# =============================================================================
# core-control — Server Provisioning
# =============================================================================
# Provisions a bare Ubuntu server as a Docker host for core-node blockchain
# producers. Installs all dependencies, configures Docker, UFW, and system
# tuning. Idempotent — safe to re-run.
#
# Usage: sudo ./setup.sh [--core-node-dir PATH] [--data-root PATH] [--ssh-port PORT]
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Script directory
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Defaults (overridable via args or environment)
# ---------------------------------------------------------------------------
CORE_NODE_DIR="${CORE_NODE_DIR:-/opt/core-node}"
CORE_NODE_REPO="${CORE_NODE_REPO:-https://github.com/AnvoIO/core-node.git}"
DATA_ROOT="${DATA_ROOT:-/data}"
SSH_PORT="${SSH_PORT:-22}"

# ---------------------------------------------------------------------------
# Colors (inline — common.sh may not be available yet)
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

_log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
_log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
_log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
_log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
_log_header()  {
    echo ""
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo ""
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --core-node-dir)
            CORE_NODE_DIR="$2"; shift 2 ;;
        --data-root)
            DATA_ROOT="$2"; shift 2 ;;
        --ssh-port)
            SSH_PORT="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: sudo $(basename "$0") [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --core-node-dir PATH  Path to clone core-node (default: /opt/core-node)"
            echo "  --data-root PATH      Root data directory (default: /data)"
            echo "  --ssh-port PORT       SSH port for UFW (default: 22)"
            exit 0
            ;;
        *)
            _log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    _log_error "This script must be run as root (or with sudo)."
    exit 1
fi

_log_header "core-control — Server Provisioning"
_log_info "Core-node dir: ${CORE_NODE_DIR}"
_log_info "Data root:     ${DATA_ROOT}"
_log_info "SSH port:      ${SSH_PORT}"
echo ""

# =========================================================================
# Phase 1: System packages
# =========================================================================
_log_header "Phase 1: System Packages"

export DEBIAN_FRONTEND=noninteractive

_log_info "Updating package lists..."
apt-get update -qq

_log_info "Installing system packages..."
apt-get install -y -qq \
    curl wget jq zstd git whiptail \
    ca-certificates gnupg lsb-release \
    btrfs-progs htop iotop tmux \
    ufw \
    > /dev/null

_log_success "System packages installed."

# =========================================================================
# Phase 2–3: Docker Engine + UFW + ufw-docker
# =========================================================================
_log_header "Phase 2-3: Docker + UFW"

OPERATOR_USER="${SUDO_USER:-sysop}"
"${SCRIPT_DIR}/scripts/server/install-docker.sh" --ssh-port "$SSH_PORT"

# =========================================================================
# Phase 4: Clone core-node
# =========================================================================
_log_header "Phase 4: core-node Repository"

if [[ -d "${CORE_NODE_DIR}/.git" ]]; then
    _log_info "core-node already present at ${CORE_NODE_DIR}."
    _log_info "Pulling latest changes..."
    git -C "$CORE_NODE_DIR" pull --ff-only 2>/dev/null || \
        _log_warn "Could not pull (branch may have diverged). Skipping update."
else
    _log_info "Cloning core-node to ${CORE_NODE_DIR}..."
    git clone "$CORE_NODE_REPO" "$CORE_NODE_DIR"
fi

_log_success "core-node ready at ${CORE_NODE_DIR}."

# =========================================================================
# Phase 5: Data directories
# =========================================================================
_log_header "Phase 5: Data Directories"

mkdir -p "${DATA_ROOT}/libre/mainnet"
mkdir -p "${DATA_ROOT}/libre/testnet"
_log_info "Created ${DATA_ROOT}/libre/{mainnet,testnet}"

# Check BTRFS
FS_TYPE="$(df -T "$DATA_ROOT" 2>/dev/null | awk 'NR==2 {print $2}')"
if [[ "$FS_TYPE" == "btrfs" ]]; then
    _log_success "Data root is on BTRFS."
else
    _log_warn "Data root ${DATA_ROOT} is on ${FS_TYPE} (not BTRFS)."
    _log_warn "BTRFS is recommended for filesystem snapshot support."
fi

# =========================================================================
# Phase 6: System tuning
# =========================================================================
_log_header "Phase 6: System Tuning"

# vm.max_map_count (required for large chain state databases)
CURRENT_MAP_COUNT="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
if (( CURRENT_MAP_COUNT < 262144 )); then
    sysctl -w vm.max_map_count=262144 >/dev/null
    echo "vm.max_map_count=262144" > /etc/sysctl.d/99-core-control.conf
    _log_info "Set vm.max_map_count=262144"
else
    _log_info "vm.max_map_count already ${CURRENT_MAP_COUNT} (>= 262144)."
fi

# Open file limits
if [[ ! -f /etc/security/limits.d/99-core-control.conf ]]; then
    cat > /etc/security/limits.d/99-core-control.conf <<'LIMITS_EOF'
* soft nofile 65535
* hard nofile 65535
LIMITS_EOF
    _log_info "Set open file limits to 65535."
else
    _log_info "File limits already configured."
fi

_log_success "System tuning applied."

# =========================================================================
# Phase 7: Finalize
# =========================================================================
_log_header "Phase 7: Finalize"

# Write core-control.conf with actual values
cat > "${SCRIPT_DIR}/core-control.conf" <<CONF_EOF
# core-control global configuration
# Generated by setup.sh on $(date '+%Y-%m-%d %H:%M:%S')

# Path to the core-node repository
CORE_NODE_DIR=${CORE_NODE_DIR}

# Root data directory (BTRFS recommended)
DATA_ROOT=${DATA_ROOT}

# SSH port (for UFW setup)
SSH_PORT=${SSH_PORT}
CONF_EOF
_log_info "Wrote core-control.conf"

# Make entry point executable
chmod +x "${SCRIPT_DIR}/core-control" 2>/dev/null || true

# Symlink for global access
ln -sf "${SCRIPT_DIR}/core-control" /usr/local/bin/core-control
_log_info "Symlinked core-control -> /usr/local/bin/core-control"

# Set ownership of nodes/ and inventory/ to the operator user
if id "$OPERATOR_USER" &>/dev/null; then
    chown -R "${OPERATOR_USER}:${OPERATOR_USER}" "${SCRIPT_DIR}/nodes" "${SCRIPT_DIR}/inventory"
fi

# =========================================================================
# Summary
# =========================================================================
_log_header "Setup Complete"

echo "  Docker:      $(docker --version 2>/dev/null || echo 'not found')"
echo "  Compose:     $(docker compose version 2>/dev/null || echo 'not found')"
echo "  UFW:         $(ufw status | head -1)"
echo "  core-node:   ${CORE_NODE_DIR}"
echo "  Data root:   ${DATA_ROOT} (${FS_TYPE})"
echo ""
_log_info "Next steps:"
echo "  1. Create an inventory file:  inventory/nodes.inv"
echo "  2. Import nodes:              core-control import inventory/nodes.inv"
echo "  3. Or add nodes manually:     core-control add-node"
echo "  4. Launch the console:        core-control"
echo ""
