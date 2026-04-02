#!/bin/bash

# =============================================================================
# core-control — OS Hardening
# =============================================================================
# Hardens a fresh Ubuntu server with SSH lockdown, fail2ban, sysctl tuning,
# and unattended security updates. Idempotent — safe to re-run.
#
# Usage: sudo ./harden.sh [--ssh-port PORT] [--ssh-user USER]
#
# What this script does:
#   1. SSH hardening (disable root login, password auth, empty passwords)
#   2. fail2ban installation and SSH jail configuration
#   3. Kernel/network sysctl hardening
#   4. Unattended security upgrades
#   5. Disable unused network services
#   6. Set restrictive default permissions
#
# This script does NOT configure UFW — that's handled by setup.sh.
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
SSH_USER="${SSH_USER:-${SUDO_USER:-sysop}}"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-port)  SSH_PORT="$2"; shift 2 ;;
        --ssh-user)  SSH_USER="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: sudo $(basename "$0") [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --ssh-port PORT   SSH port (default: 22)"
            echo "  --ssh-user USER   Allowed SSH user (default: \$SUDO_USER or sysop)"
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

_log_header "OS Hardening"
_log_info "SSH port:  ${SSH_PORT}"
_log_info "SSH user:  ${SSH_USER}"
echo ""

# =========================================================================
# Phase 1: SSH Hardening
# =========================================================================
_log_header "Phase 1: SSH Hardening"

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_HARDENING="/etc/ssh/sshd_config.d/99-hardening.conf"

# Use sshd_config.d drop-in if supported (Ubuntu 22.04+), otherwise
# modify sshd_config directly.
if [[ -d /etc/ssh/sshd_config.d ]] && grep -q "Include /etc/ssh/sshd_config.d" "$SSHD_CONFIG" 2>/dev/null; then
    _log_info "Using sshd_config.d drop-in: ${SSHD_HARDENING}"
    cat > "$SSHD_HARDENING" <<EOF
# core-control SSH hardening — $(date '+%Y-%m-%d')
Port ${SSH_PORT}
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers ${SSH_USER}
EOF
else
    _log_info "Modifying ${SSHD_CONFIG} directly"

    # Backup original
    if [[ ! -f "${SSHD_CONFIG}.orig" ]]; then
        cp "$SSHD_CONFIG" "${SSHD_CONFIG}.orig"
        _log_info "Backed up original to ${SSHD_CONFIG}.orig"
    fi

    # Apply settings via sed (idempotent — handles both commented and active lines)
    apply_sshd_setting() {
        local key="$1" value="$2"
        if grep -qE "^#?\s*${key}\b" "$SSHD_CONFIG"; then
            sed -i "s|^#*\s*${key}\b.*|${key} ${value}|" "$SSHD_CONFIG"
        else
            echo "${key} ${value}" >> "$SSHD_CONFIG"
        fi
    }

    apply_sshd_setting "Port" "$SSH_PORT"
    apply_sshd_setting "PermitRootLogin" "no"
    apply_sshd_setting "PasswordAuthentication" "no"
    apply_sshd_setting "PermitEmptyPasswords" "no"
    apply_sshd_setting "ChallengeResponseAuthentication" "no"
    apply_sshd_setting "X11Forwarding" "no"
    apply_sshd_setting "AllowTcpForwarding" "no"
    apply_sshd_setting "AllowAgentForwarding" "no"
    apply_sshd_setting "MaxAuthTries" "3"
    apply_sshd_setting "MaxSessions" "3"
    apply_sshd_setting "LoginGraceTime" "30"
    apply_sshd_setting "ClientAliveInterval" "300"
    apply_sshd_setting "ClientAliveCountMax" "2"

    # AllowUsers — append if not present, replace if present
    if grep -qE "^AllowUsers\b" "$SSHD_CONFIG"; then
        sed -i "s|^AllowUsers\b.*|AllowUsers ${SSH_USER}|" "$SSHD_CONFIG"
    else
        echo "AllowUsers ${SSH_USER}" >> "$SSHD_CONFIG"
    fi
fi

# Validate config before restarting
if sshd -t 2>/dev/null; then
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    _log_success "SSH hardened and restarted."
else
    _log_error "sshd config validation failed! Reverting..."
    if [[ -f "$SSHD_HARDENING" ]]; then
        rm -f "$SSHD_HARDENING"
    elif [[ -f "${SSHD_CONFIG}.orig" ]]; then
        cp "${SSHD_CONFIG}.orig" "$SSHD_CONFIG"
    fi
    _log_error "Fix SSH config manually before re-running."
    exit 1
fi

# =========================================================================
# Phase 2: fail2ban
# =========================================================================
_log_header "Phase 2: fail2ban"

export DEBIAN_FRONTEND=noninteractive

if ! command -v fail2ban-client &>/dev/null; then
    _log_info "Installing fail2ban..."
    apt-get update -qq
    apt-get install -y -qq fail2ban > /dev/null
fi

# Configure SSH jail
JAIL_LOCAL="/etc/fail2ban/jail.local"
cat > "$JAIL_LOCAL" <<EOF
# core-control fail2ban config — $(date '+%Y-%m-%d')
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
banaction = ufw

[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

systemctl enable fail2ban --now 2>/dev/null || true
systemctl restart fail2ban 2>/dev/null || true

_log_success "fail2ban configured (SSH jail: 3 retries, 1h ban)."

# =========================================================================
# Phase 3: Kernel / Network Hardening (sysctl)
# =========================================================================
_log_header "Phase 3: Kernel Hardening"

SYSCTL_CONF="/etc/sysctl.d/99-hardening.conf"
cat > "$SYSCTL_CONF" <<'SYSCTL_EOF'
# core-control kernel hardening

# Prevent IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Disable ICMP redirects (not a router)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Ignore ICMP broadcasts
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Log martian packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_synack_retries = 2

# Disable IPv6 if not needed (uncomment if desired)
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1

# Protect against TIME-WAIT assassination
net.ipv4.tcp_rfc1337 = 1

# Disable IP forwarding (not a router)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Restrict dmesg access
kernel.dmesg_restrict = 1

# Restrict kernel pointer exposure
kernel.kptr_restrict = 2

# Restrict ptrace (process debugging)
kernel.yama.ptrace_scope = 2
SYSCTL_EOF

sysctl --system > /dev/null 2>&1

# Docker requires ip_forward — will be enabled by Docker daemon.
# The sysctl above sets it to 0 for hardening pre-Docker. Docker's
# systemd unit overrides this when it starts.
_log_info "Note: net.ipv4.ip_forward=0 set. Docker will enable it when started."

_log_success "Kernel hardening applied."

# =========================================================================
# Phase 4: Unattended Security Upgrades
# =========================================================================
_log_header "Phase 4: Unattended Upgrades"

apt-get install -y -qq unattended-upgrades > /dev/null

# Enable automatic security updates
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'APT_EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT_EOF

# Configure to only apply security updates (not all updates)
UNATTENDED_CONF="/etc/apt/apt.conf.d/50unattended-upgrades"
if [[ -f "$UNATTENDED_CONF" ]]; then
    # Ensure security updates are enabled (they usually are by default)
    if grep -q '//.*"${distro_id}:${distro_codename}-security"' "$UNATTENDED_CONF"; then
        sed -i 's|//\(.*"${distro_id}:${distro_codename}-security"\)|\1|' "$UNATTENDED_CONF"
    fi

    # Enable automatic reboot if required (at 4 AM)
    if grep -q '//Unattended-Upgrade::Automatic-Reboot "' "$UNATTENDED_CONF"; then
        sed -i 's|//\(Unattended-Upgrade::Automatic-Reboot "\)false|\1true|' "$UNATTENDED_CONF"
    fi
    if grep -q '//Unattended-Upgrade::Automatic-Reboot-Time' "$UNATTENDED_CONF"; then
        sed -i 's|//\(Unattended-Upgrade::Automatic-Reboot-Time\).*|\1 "04:00";|' "$UNATTENDED_CONF"
    fi
fi

systemctl enable unattended-upgrades 2>/dev/null || true

_log_success "Unattended security upgrades configured."

# =========================================================================
# Phase 5: Disable Unused Services
# =========================================================================
_log_header "Phase 5: Disable Unused Services"

# Disable services that are commonly enabled but not needed on a node server
for svc in cups avahi-daemon rpcbind snapd; do
    if systemctl is-active "$svc" &>/dev/null; then
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
        _log_info "Disabled: ${svc}"
    fi
done

_log_success "Unused services check complete."

# =========================================================================
# Phase 6: File Permission Hardening
# =========================================================================
_log_header "Phase 6: File Permissions"

# Restrict cron to root and the SSH user
if [[ ! -f /etc/cron.allow ]]; then
    echo "root" > /etc/cron.allow
    echo "$SSH_USER" >> /etc/cron.allow
    chmod 640 /etc/cron.allow
    _log_info "Created /etc/cron.allow (root + ${SSH_USER})"
fi

# Restrict at to root
if [[ ! -f /etc/at.allow ]]; then
    echo "root" > /etc/at.allow
    chmod 640 /etc/at.allow
    _log_info "Created /etc/at.allow (root only)"
fi

# Set default umask to 027 (owner=rwx, group=rx, other=none)
UMASK_FILE="/etc/profile.d/99-umask.sh"
if [[ ! -f "$UMASK_FILE" ]]; then
    echo "umask 027" > "$UMASK_FILE"
    _log_info "Set default umask to 027"
fi

_log_success "File permissions hardened."

# =========================================================================
# Summary
# =========================================================================
_log_header "Hardening Complete"

echo "  SSH:         Port ${SSH_PORT}, root disabled, key-only auth"
echo "  SSH user:    ${SSH_USER}"
echo "  fail2ban:    SSH jail active (3 tries, 1h ban)"
echo "  Sysctl:      Network and kernel hardening applied"
echo "  Updates:     Unattended security upgrades enabled"
echo ""
_log_warn "IMPORTANT: Verify you can SSH in on port ${SSH_PORT} before closing"
_log_warn "this session. If you changed the SSH port, update UFW rules."
echo ""
