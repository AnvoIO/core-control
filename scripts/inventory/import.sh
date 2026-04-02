#!/bin/bash

# =============================================================================
# core-control — Inventory Import
# =============================================================================
# Parses a .inv inventory file and creates node.conf files + generated configs
# for each node. This is the core data pipeline.
#
# Inventory format (pipe-delimited):
#   CONTAINER_NAME|NETWORK|NODE_ROLE|BIND_IP|HTTP_PORT|P2P_PORT|PRODUCER_NAME|SIGNATURE_PROVIDER|LOG_PROFILE|SNAPSHOT_INTERVAL|SNAPSHOT_RETENTION|MAX_RETAINED_BLOCK_FILES|BLOCKS_LOG_STRIDE
#
# Fields after SIGNATURE_PROVIDER are optional (defaults applied).
# Lines starting with # are comments. Blank lines are skipped.
#
# Usage: import.sh <inventory_file> [--skip-generate] [--skip-firewall]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"
source "${SCRIPT_DIR}/../lib/ufw-helpers.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
INV_FILE=""
SKIP_GENERATE=false
SKIP_FIREWALL=false

for arg in "$@"; do
    case "$arg" in
        --skip-generate) SKIP_GENERATE=true ;;
        --skip-firewall) SKIP_FIREWALL=true ;;
        -*)
            log_error "Unknown option: ${arg}"
            exit 1
            ;;
        *)
            if [[ -z "$INV_FILE" ]]; then
                INV_FILE="$arg"
            else
                log_error "Unexpected argument: ${arg}"
                exit 1
            fi
            ;;
    esac
done

if [[ -z "$INV_FILE" ]]; then
    log_error "Usage: $(basename "$0") <inventory_file> [--skip-generate] [--skip-firewall]"
    exit 1
fi

# Resolve relative paths
if [[ "$INV_FILE" != /* ]]; then
    INV_FILE="${PWD}/${INV_FILE}"
fi

# ---------------------------------------------------------------------------
# Validate first
# ---------------------------------------------------------------------------
log_header "core-control — Import Inventory"

log_info "Validating ${INV_FILE}..."
if ! "${SCRIPT_DIR}/validate.sh" "$INV_FILE"; then
    log_error "Fix validation errors before importing."
    exit 1
fi

# ---------------------------------------------------------------------------
# Import each node
# ---------------------------------------------------------------------------
imported=0
skipped=0
errors=0

while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    IFS='|' read -ra fields <<< "$line"

    local_container_name="${fields[0]}"
    local_network="${fields[1]}"
    local_node_role="${fields[2]}"
    local_bind_ip="${fields[3]}"
    local_http_port="${fields[4]}"
    local_p2p_port="${fields[5]}"
    local_producer_name="${fields[6]:-}"
    local_sig_provider="${fields[7]:-}"
    local_log_profile="${fields[8]:-standard}"
    local_snapshot_interval="${fields[9]:-100000}"
    local_snapshot_retention="${fields[10]:-10}"
    local_max_retained_block_files="${fields[11]:-10}"
    local_blocks_log_stride="${fields[12]:-100000}"

    # Default empty optional fields
    [[ -z "$local_log_profile" ]] && local_log_profile="standard"
    [[ -z "$local_snapshot_interval" ]] && local_snapshot_interval="100000"
    [[ -z "$local_snapshot_retention" ]] && local_snapshot_retention="10"
    [[ -z "$local_max_retained_block_files" ]] && local_max_retained_block_files="10"
    [[ -z "$local_blocks_log_stride" ]] && local_blocks_log_stride="100000"

    # Check if node already exists
    if [[ -f "${NODES_DIR}/${local_container_name}/node.conf" ]]; then
        log_warn "Node '${local_container_name}' already exists — skipping."
        skipped=$((skipped + 1))
        continue
    fi

    log_info "Importing ${local_container_name} (${local_network}/${local_node_role})..."

    # Derive storage path
    local_storage_name="${local_producer_name:-$local_container_name}"
    local_storage_path="${DATA_ROOT}/libre/${local_network}/${local_storage_name}"

    # Create node.conf and populate it
    local_conf_path="$(create_node_conf "$local_container_name")"

    write_node_config \
        "$local_container_name" \
        "$local_network" \
        "$local_node_role" \
        "$local_bind_ip" \
        "$local_http_port" \
        "$local_p2p_port" \
        "$local_storage_path" \
        "$local_log_profile" \
        "$local_snapshot_interval" \
        "$local_snapshot_retention" \
        "$local_blocks_log_stride" \
        "$local_max_retained_block_files" \
        "$local_producer_name" \
        "$local_sig_provider"

    # Run generate-config.sh to create docker-compose, config.ini, etc.
    if [[ "$SKIP_GENERATE" != "true" ]]; then
        if ! "${CORE_NODE_DIR}/scripts/setup/generate-config.sh" "$local_conf_path"; then
            log_error "Failed to generate config for ${local_container_name}"
            errors=$((errors + 1))
            continue
        fi
    fi

    # Apply firewall rules
    if [[ "$SKIP_FIREWALL" != "true" ]]; then
        apply_node_rules "$local_conf_path" || true
    fi

    imported=$((imported + 1))
    log_success "Imported ${local_container_name}"

done < "$INV_FILE"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_header "Import Complete"

echo "  Imported: ${imported}"
echo "  Skipped:  ${skipped}"
echo "  Errors:   ${errors}"
echo ""

if (( imported > 0 )); then
    log_info "To start all nodes:  core-control start-all"
    log_info "To view dashboard:   core-control"
fi

if (( errors > 0 )); then
    exit 1
fi
