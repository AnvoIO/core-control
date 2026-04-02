#!/bin/bash

# =============================================================================
# core-control — Inventory File Validator
# =============================================================================
# Validates a .inv inventory file format before import.
#
# Usage: validate.sh <inventory_file>
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
VALID_NETWORKS="mainnet testnet"
VALID_ROLES="producer seed light-api full-api full-history"
MIN_FIELDS=6

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local inv_file="${1:-}"

    if [[ -z "$inv_file" ]]; then
        log_error "Usage: $(basename "$0") <inventory_file>"
        exit 1
    fi

    if [[ ! -f "$inv_file" ]]; then
        log_error "Inventory file not found: ${inv_file}"
        exit 1
    fi

    local errors=0
    local line_num=0
    local -A seen_names=()
    local -A seen_ports=()  # key: "bind_ip:port"

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        IFS='|' read -ra fields <<< "$line"
        local field_count=${#fields[@]}

        # Check minimum field count
        if (( field_count < MIN_FIELDS )); then
            log_error "Line ${line_num}: Expected at least ${MIN_FIELDS} fields, got ${field_count}"
            errors=$((errors + 1))
            continue
        fi

        local container_name="${fields[0]}"
        local network="${fields[1]}"
        local node_role="${fields[2]}"
        local bind_ip="${fields[3]}"
        local http_port="${fields[4]}"
        local p2p_port="${fields[5]}"
        local ship_port="${fields[6]:-}"
        local producer_name="${fields[7]:-}"

        # Validate container name
        if [[ -z "$container_name" ]]; then
            log_error "Line ${line_num}: CONTAINER_NAME is empty"
            errors=$((errors + 1))
        elif [[ ! "$container_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
            log_error "Line ${line_num}: Invalid CONTAINER_NAME '${container_name}' (use alphanumeric, dots, hyphens, underscores)"
            errors=$((errors + 1))
        fi

        # Check for duplicate container names
        if [[ -n "${seen_names[$container_name]+x}" ]]; then
            log_error "Line ${line_num}: Duplicate CONTAINER_NAME '${container_name}' (first on line ${seen_names[$container_name]})"
            errors=$((errors + 1))
        else
            seen_names["$container_name"]="$line_num"
        fi

        # Validate network
        if ! echo "$VALID_NETWORKS" | grep -qw "$network"; then
            log_error "Line ${line_num}: Invalid NETWORK '${network}' (expected: ${VALID_NETWORKS})"
            errors=$((errors + 1))
        fi

        # Validate role
        if ! echo "$VALID_ROLES" | grep -qw "$node_role"; then
            log_error "Line ${line_num}: Invalid NODE_ROLE '${node_role}' (expected: ${VALID_ROLES})"
            errors=$((errors + 1))
        fi

        # Validate IP
        if ! validate_ip "$bind_ip"; then
            log_error "Line ${line_num}: Invalid BIND_IP '${bind_ip}'"
            errors=$((errors + 1))
        fi

        # Validate ports
        if [[ "$node_role" != "seed" ]]; then
            if ! validate_port "$http_port"; then
                log_error "Line ${line_num}: Invalid HTTP_PORT '${http_port}'"
                errors=$((errors + 1))
            fi
        fi

        if ! validate_port "$p2p_port"; then
            log_error "Line ${line_num}: Invalid P2P_PORT '${p2p_port}'"
            errors=$((errors + 1))
        fi

        # Validate SHIP_PORT if provided
        if [[ -n "$ship_port" ]]; then
            if ! validate_port "$ship_port"; then
                log_error "Line ${line_num}: Invalid SHIP_PORT '${ship_port}'"
                errors=$((errors + 1))
            fi
        fi

        # Check for port conflicts on same bind IP
        local http_key="${bind_ip}:${http_port}"
        local p2p_key="${bind_ip}:${p2p_port}"

        if [[ -n "$http_port" && -n "${seen_ports[$http_key]+x}" ]]; then
            log_error "Line ${line_num}: Port conflict — ${http_key} already used by ${seen_ports[$http_key]}"
            errors=$((errors + 1))
        elif [[ -n "$http_port" ]]; then
            seen_ports["$http_key"]="$container_name"
        fi

        if [[ -n "${seen_ports[$p2p_key]+x}" ]]; then
            log_error "Line ${line_num}: Port conflict — ${p2p_key} already used by ${seen_ports[$p2p_key]}"
            errors=$((errors + 1))
        else
            seen_ports["$p2p_key"]="$container_name"
        fi

        if [[ -n "$ship_port" ]]; then
            local ship_key="${bind_ip}:${ship_port}"
            if [[ -n "${seen_ports[$ship_key]+x}" ]]; then
                log_error "Line ${line_num}: Port conflict — ${ship_key} already used by ${seen_ports[$ship_key]}"
                errors=$((errors + 1))
            else
                seen_ports["$ship_key"]="$container_name"
            fi
        fi

        # Producer-specific validation
        if [[ "$node_role" == "producer" ]]; then
            if [[ -z "$producer_name" ]]; then
                log_error "Line ${line_num}: PRODUCER_NAME required for producer role"
                errors=$((errors + 1))
            fi
            local sig_provider="${fields[8]:-}"
            if [[ -z "$sig_provider" ]]; then
                log_error "Line ${line_num}: SIGNATURE_PROVIDER required for producer role"
                errors=$((errors + 1))
            fi
        fi

    done < "$inv_file"

    if (( errors > 0 )); then
        log_error "Validation failed with ${errors} error(s)."
        return 1
    fi

    local count
    count="$(grep -cv '^\s*#\|^\s*$' "$inv_file" 2>/dev/null || echo 0)"
    log_success "Inventory valid: ${count} node(s) defined."
    return 0
}

main "$@"
