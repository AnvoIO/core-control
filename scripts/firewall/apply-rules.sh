#!/bin/bash

# =============================================================================
# core-control — Apply UFW Rules for a Single Node
# =============================================================================
# Reads a node.conf and applies role-appropriate UFW rules.
#
# Usage: apply-rules.sh <path/to/node.conf>
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"
source "${SCRIPT_DIR}/../lib/ufw-helpers.sh"

main() {
    local conf_path="${1:-}"

    if [[ -z "$conf_path" ]]; then
        log_error "Usage: $(basename "$0") <path/to/node.conf>"
        exit 1
    fi

    if [[ ! -f "$conf_path" ]]; then
        log_error "Config not found: ${conf_path}"
        exit 1
    fi

    apply_node_rules "$conf_path"
}

main "$@"
