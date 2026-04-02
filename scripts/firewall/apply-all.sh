#!/bin/bash

# =============================================================================
# core-control — Apply UFW Rules for All Nodes
# =============================================================================
# Iterates all registered nodes and applies firewall rules for each.
#
# Usage: apply-all.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"
source "${SCRIPT_DIR}/../lib/ufw-helpers.sh"

main() {
    log_header "core-control — Apply All Firewall Rules"

    local count=0
    local name
    for name in $(list_all_nodes); do
        local conf
        conf="$(get_node_conf "$name")" || continue
        apply_node_rules "$conf"
        count=$((count + 1))
    done

    if (( count == 0 )); then
        log_info "No nodes registered."
    else
        log_success "Applied firewall rules for ${count} node(s)."
    fi
}

main "$@"
