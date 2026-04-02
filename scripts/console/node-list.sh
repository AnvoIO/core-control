#!/bin/bash

# =============================================================================
# core-control — Node List / Dashboard (TUI)
# =============================================================================
# Shows all registered nodes with status. Selecting a node opens the
# per-node actions menu.
#
# Usage:
#   node-list.sh               Select a node for actions
#   node-list.sh --view-only   Dashboard view (no selection)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"

require_whiptail

VIEW_ONLY=false
[[ "${1:-}" == "--view-only" ]] && VIEW_ONLY=true

# ---------------------------------------------------------------------------
# Fetch statuses once, reuse for both paths
# ---------------------------------------------------------------------------
ALL_STATUSES="$(get_all_node_statuses)"

if [[ -z "$ALL_STATUSES" ]]; then
    cc_msgbox "Node Dashboard" "No nodes registered.\n\nUse 'Add Node' or 'Import Inventory' from the main menu."
    exit 0
fi

# ---------------------------------------------------------------------------
# View-only dashboard
# ---------------------------------------------------------------------------
if [[ "$VIEW_ONLY" == "true" ]]; then
    tmpfile="$(mktemp)"
    {
        echo "Node Dashboard"
        echo "=============="
        echo ""
        printf "%-35s %s\n" "CONTAINER" "STATUS"
        printf "%-35s %s\n" "---------" "------"

        while IFS='|' read -r name status network role bind_ip http_port; do
            [[ -z "$name" ]] && continue
            indicator="DOWN"
            [[ "$status" == "RUNNING" ]] && indicator=" UP "
            printf "%-35s [%s] %s/%s %s:%s\n" \
                "$name" "$indicator" "$network" "$role" "$bind_ip" "${http_port:-n/a}"
        done <<< "$ALL_STATUSES"
    } > "$tmpfile"
    cc_textbox "Node Dashboard" "$tmpfile"
    rm -f "$tmpfile"
    exit 0
fi

# ---------------------------------------------------------------------------
# Interactive mode — build menu items with head block info for running nodes
# ---------------------------------------------------------------------------
build_menu_items() {
    local items=()
    while IFS='|' read -r name status network role bind_ip http_port; do
        [[ -z "$name" ]] && continue

        local indicator="DOWN"
        local block_info=""

        if [[ "$status" == "RUNNING" ]]; then
            indicator=" UP "

            # Quick head block check (non-blocking, 2s timeout)
            if [[ "$role" != "seed" && -n "$http_port" ]]; then
                local api_host="$bind_ip"
                [[ "$api_host" == "0.0.0.0" ]] && api_host="localhost"
                local chain_info
                if chain_info="$(curl -sf --max-time 2 \
                        "http://${api_host}:${http_port}/v1/chain/get_info" 2>/dev/null)"; then
                    local head_num
                    head_num="$(echo "$chain_info" | jq -r '.head_block_num // empty' 2>/dev/null)"
                    if [[ -n "$head_num" ]]; then
                        block_info=" blk#${head_num}"
                    fi
                fi
            fi
        fi

        local desc="[${indicator}] ${network}/${role} ${bind_ip}:${http_port:-n/a}${block_info}"
        items+=("$name" "$desc")
    done <<< "$ALL_STATUSES"

    if [[ ${#items[@]} -eq 0 ]]; then
        return 1
    fi

    printf '%s\n' "${items[@]}"
}

node_data="$(build_menu_items)" || {
    cc_msgbox "Node Dashboard" "No nodes registered."
    exit 0
}

mapfile -t menu_items <<< "$node_data"

while true; do
    selected="$(cc_menu "Manage Nodes" \
        "Select a node:" \
        "${menu_items[@]}" \
        "back" "Return to main menu")" || break

    [[ "$selected" == "back" ]] && break

    # Open per-node actions
    "${SCRIPT_DIR}/node-actions.sh" "$selected"
done
