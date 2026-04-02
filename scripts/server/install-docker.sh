#!/bin/bash

# =============================================================================
# core-control — Docker + ufw-docker Installation
# =============================================================================
# Installs Docker Engine, Docker Compose plugin, and chaifeng/ufw-docker.
# Idempotent — safe to re-run. Can be run standalone or called by setup.sh.
#
# Usage: sudo ./install-docker.sh [--ssh-port PORT]
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors (standalone — no dependency on project libs)
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
# Defaults
# ---------------------------------------------------------------------------
SSH_PORT="${SSH_PORT:-22}"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-port)  SSH_PORT="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: sudo $(basename "$0") [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --ssh-port PORT   SSH port for UFW allow rule (default: 22)"
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

export DEBIAN_FRONTEND=noninteractive

# =========================================================================
# Phase 1: Docker Engine + Compose plugin
# =========================================================================
_log_header "Docker Engine"

if command -v docker &>/dev/null; then
    _log_info "Docker already installed: $(docker --version)"
else
    _log_info "Installing Docker Engine from official repository..."

    # Prerequisites
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg > /dev/null

    # Docker GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Docker apt repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin \
        > /dev/null

    _log_success "Docker Engine installed: $(docker --version)"
fi

# Add the operator user to docker group
OPERATOR_USER="${SUDO_USER:-sysop}"
if id "$OPERATOR_USER" &>/dev/null; then
    if ! groups "$OPERATOR_USER" | grep -q '\bdocker\b'; then
        usermod -aG docker "$OPERATOR_USER"
        _log_info "Added ${OPERATOR_USER} to docker group (re-login required)."
    fi
fi

# Ensure Docker is running
systemctl enable docker --now 2>/dev/null || true
_log_success "Docker is running."

# =========================================================================
# Phase 2: UFW + ufw-docker
# =========================================================================
_log_header "UFW + ufw-docker"

# Ensure UFW is installed
if ! command -v ufw &>/dev/null; then
    _log_info "Installing UFW..."
    apt-get install -y -qq ufw > /dev/null
fi

_log_info "Configuring UFW defaults..."
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1

_log_info "Allowing SSH on port ${SSH_PORT}..."
ufw allow "$SSH_PORT/tcp" comment "SSH" >/dev/null 2>&1

# Install ufw-docker
if [[ ! -f /usr/local/bin/ufw-docker ]]; then
    _log_info "Installing ufw-docker (fixes Docker bypassing UFW)..."
    wget -qO /usr/local/bin/ufw-docker \
        https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
    chmod +x /usr/local/bin/ufw-docker
    _log_success "ufw-docker installed."
else
    _log_info "ufw-docker already installed."
fi

# Apply the after.rules patch
_log_info "Applying ufw-docker after.rules..."
ufw-docker install >/dev/null 2>&1 || true

# Enable UFW
ufw --force enable >/dev/null 2>&1
systemctl restart ufw 2>/dev/null || true

_log_success "UFW configured and enabled."

# =========================================================================
# Summary
# =========================================================================
_log_header "Docker Installation Complete"

echo "  Docker:   $(docker --version 2>/dev/null || echo 'not found')"
echo "  Compose:  $(docker compose version 2>/dev/null || echo 'not found')"
echo "  UFW:      $(ufw status | head -1)"
echo "  Operator: ${OPERATOR_USER} (in docker group)"
echo ""
