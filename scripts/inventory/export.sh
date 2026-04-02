#!/bin/bash

# =============================================================================
# core-control — Inventory Export
# =============================================================================
# Exports all registered nodes to .inv format for migration or backup.
#
# Usage: export.sh [output_file]
#   If no output file given, prints to stdout.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local output_file="${1:-}"
    local output=""

    # Header
    output+="# core-control node inventory"$'\n'
    output+="# Exported on $(date '+%Y-%m-%d %H:%M:%S')"$'\n'
    output+="# Format: CONTAINER_NAME|NETWORK|NODE_ROLE|BIND_IP|HTTP_PORT|P2P_PORT|SHIP_PORT|PRODUCER_NAME|SIGNATURE_PROVIDER|LOG_PROFILE|SNAPSHOT_INTERVAL|SNAPSHOT_RETENTION|MAX_RETAINED_BLOCK_FILES|BLOCKS_LOG_STRIDE"$'\n'
    output+="#"$'\n'

    local count=0
    local name
    for name in $(list_all_nodes); do
        local conf="${NODES_DIR}/${name}/node.conf"
        [[ -f "$conf" ]] || continue

        # Save and restore CONFIG_FILE
        local saved_config="${CONFIG_FILE:-}"
        load_config "$conf"

        local container_name network node_role bind_ip http_port p2p_port ship_port
        local producer_name sig_provider log_profile snapshot_interval snapshot_retention
        local max_retained blocks_log_stride

        container_name="$(get_config "CONTAINER_NAME" "$name")"
        network="$(get_config "NETWORK" "")"
        node_role="$(get_config "NODE_ROLE" "")"
        bind_ip="$(get_config "BIND_IP" "0.0.0.0")"
        http_port="$(get_config "HTTP_PORT" "")"
        p2p_port="$(get_config "P2P_PORT" "")"
        ship_port="$(get_config "SHIP_PORT" "")"
        producer_name="$(get_config "PRODUCER_NAME" "")"
        sig_provider="$(get_config "SIGNATURE_PROVIDER" "")"
        log_profile="$(get_config "LOG_PROFILE" "standard")"
        snapshot_interval="$(get_config "SNAPSHOT_INTERVAL" "100000")"
        snapshot_retention="$(get_config "SNAPSHOT_RETENTION" "10")"
        max_retained="$(get_config "MAX_RETAINED_BLOCK_FILES" "10")"
        blocks_log_stride="$(get_config "BLOCKS_LOG_STRIDE" "100000")"

        output+="${container_name}|${network}|${node_role}|${bind_ip}|${http_port}|${p2p_port}|${ship_port}|${producer_name}|${sig_provider}|${log_profile}|${snapshot_interval}|${snapshot_retention}|${max_retained}|${blocks_log_stride}"$'\n'

        CONFIG_FILE="$saved_config"
        count=$((count + 1))
    done

    if [[ -n "$output_file" ]]; then
        echo -n "$output" > "$output_file"
        log_success "Exported ${count} node(s) to ${output_file}"
    else
        echo -n "$output"
    fi
}

main "$@"
