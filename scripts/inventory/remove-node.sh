#!/bin/bash

# =============================================================================
# core-control — Remove Node
# =============================================================================
# Stops a node, removes its UFW rules, and deletes its node.conf from the
# nodes/ directory. Does NOT delete the node's data (STORAGE_PATH).
#
# Usage: remove-node.sh <CONTAINER_NAME> [--force]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"
source "${SCRIPT_DIR}/../lib/ufw-helpers.sh"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local container_name="${1:-}"
    local force=false
    [[ "${2:-}" == "--force" ]] && force=true

    if [[ -z "$container_name" ]]; then
        log_error "Usage: $(basename "$0") <CONTAINER_NAME> [--force]"
        exit 1
    fi

    local node_dir="${NODES_DIR}/${container_name}"
    local conf_path="${node_dir}/node.conf"

    if [[ ! -d "$node_dir" ]]; then
        log_error "Node '${container_name}' not found in ${NODES_DIR}/"
        exit 1
    fi

    # Read storage path for info
    local storage_path=""
    if [[ -f "$conf_path" ]]; then
        storage_path="$(grep "^STORAGE_PATH=" "$conf_path" 2>/dev/null | cut -d= -f2- || true)"
    fi

    # Confirm unless --force
    if [[ "$force" != "true" ]]; then
        echo ""
        log_warn "About to remove node: ${container_name}"
        echo "  This will:"
        echo "    - Stop the container (if running)"
        echo "    - Remove UFW firewall rules"
        echo "    - Delete node config from ${node_dir}/"
        echo ""
        echo "  This will NOT delete node data at:"
        echo "    ${storage_path:-<unknown>}"
        echo ""

        if ! ask_yes_no "Remove ${container_name}?" "n"; then
            log_info "Cancelled."
            exit 0
        fi
    fi

    # Stop the container if running
    if command -v docker &>/dev/null; then
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            log_info "Stopping ${container_name}..."
            if [[ -n "$storage_path" && -f "${storage_path}/config/docker-compose.yml" ]]; then
                docker compose -f "${storage_path}/config/docker-compose.yml" down --timeout 1800 || true
            else
                docker stop -t 1800 "$container_name" 2>/dev/null || true
                docker rm "$container_name" 2>/dev/null || true
            fi
        fi
    fi

    # Remove UFW rules
    remove_node_rules "$container_name"

    # Remove node directory
    rm -rf "$node_dir"
    log_success "Node '${container_name}' removed."

    if [[ -n "$storage_path" ]]; then
        log_info "Node data remains at: ${storage_path}"
        log_info "Delete manually if no longer needed: sudo rm -rf ${storage_path}"
    fi
}

main "$@"
