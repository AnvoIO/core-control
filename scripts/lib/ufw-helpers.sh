#!/bin/bash

# =============================================================================
# core-control — UFW Firewall Helpers
# =============================================================================
# Manages UFW rules for core-node instances. Rules are tagged with
# "core-control:" comments for easy identification and removal.
#
# Source this file from other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/ufw-helpers.sh"
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Source guard
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

if [[ "${_UFW_HELPERS_SH_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_UFW_HELPERS_SH_LOADED="true"

# ---------------------------------------------------------------------------
# apply_node_rules "path/to/node.conf"
# Reads node config and applies UFW rules based on role.
# - P2P port: allow from any (required for blockchain peering)
# - HTTP port: role-dependent (producer=localhost, API=public, seed=skip)
# ---------------------------------------------------------------------------
apply_node_rules() {
    local conf_path="$1"

    if ! command -v ufw &>/dev/null; then
        log_warn "ufw not found — skipping firewall rules."
        return 0
    fi

    # Save and restore CONFIG_FILE to avoid clobbering caller's state
    local saved_config_file="${CONFIG_FILE:-}"
    load_config "$conf_path"

    local container_name bind_ip http_port p2p_port node_role ship_port
    container_name="$(get_config "CONTAINER_NAME")"
    bind_ip="$(get_config "BIND_IP" "0.0.0.0")"
    http_port="$(get_config "HTTP_PORT" "")"
    p2p_port="$(get_config "P2P_PORT")"
    node_role="$(get_config "NODE_ROLE")"
    ship_port="$(get_config "SHIP_PORT" "")"

    log_info "Applying UFW rules for ${container_name} (${node_role})..."

    # P2P port — always public
    ufw allow to "$bind_ip" port "$p2p_port" proto tcp \
        comment "core-control: ${container_name} P2P" >/dev/null 2>&1 || true

    # HTTP API port — role-dependent
    case "$node_role" in
        producer)
            # Producer API: localhost only (producer_api_plugin is sensitive)
            if [[ -n "$http_port" ]]; then
                ufw allow from 127.0.0.1 to "$bind_ip" port "$http_port" proto tcp \
                    comment "core-control: ${container_name} HTTP (local)" >/dev/null 2>&1 || true
            fi
            ;;
        seed)
            # No HTTP port for seed nodes
            ;;
        light-api|full-api|full-history)
            if [[ -n "$http_port" ]]; then
                ufw allow to "$bind_ip" port "$http_port" proto tcp \
                    comment "core-control: ${container_name} HTTP API" >/dev/null 2>&1 || true
            fi
            ;;
    esac

    # SHiP port (if applicable)
    if [[ -n "$ship_port" ]]; then
        ufw allow to "$bind_ip" port "$ship_port" proto tcp \
            comment "core-control: ${container_name} SHiP" >/dev/null 2>&1 || true
    fi

    log_success "UFW rules applied for ${container_name}."

    # Restore caller's config state
    CONFIG_FILE="$saved_config_file"
}

# ---------------------------------------------------------------------------
# remove_node_rules "CONTAINER_NAME"
# Removes all UFW rules tagged with this container name.
# ---------------------------------------------------------------------------
remove_node_rules() {
    local container_name="$1"

    if ! command -v ufw &>/dev/null; then
        log_warn "ufw not found — skipping firewall rule removal."
        return 0
    fi

    log_info "Removing UFW rules for ${container_name}..."

    # Get rule numbers matching this container, in reverse order (so deleting
    # doesn't shift subsequent numbers)
    local rule_nums
    rule_nums="$(ufw status numbered 2>/dev/null \
        | grep "core-control: ${container_name} " \
        | sed 's/^\[[ ]*\([0-9]*\)\].*/\1/' \
        | sort -rn)" || true

    if [[ -z "$rule_nums" ]]; then
        log_info "No UFW rules found for ${container_name}."
        return 0
    fi

    local num
    while IFS= read -r num; do
        [[ -z "$num" ]] && continue
        ufw --force delete "$num" >/dev/null 2>&1 || true
    done <<< "$rule_nums"

    log_success "UFW rules removed for ${container_name}."
}

# ---------------------------------------------------------------------------
# list_managed_rules
# Displays all core-control-managed UFW rules.
# ---------------------------------------------------------------------------
list_managed_rules() {
    if ! command -v ufw &>/dev/null; then
        log_warn "ufw not found."
        return 0
    fi

    echo "core-control managed UFW rules:"
    echo "================================"
    ufw status numbered 2>/dev/null | grep "core-control:" || echo "  (none)"
    echo ""
}
