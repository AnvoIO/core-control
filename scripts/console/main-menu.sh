#!/bin/bash

# =============================================================================
# core-control — Main Menu (TUI)
# =============================================================================
# Top-level whiptail menu loop.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"

require_whiptail

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
while true; do
    node_total="$(node_count)"

    choice="$(cc_menu "core-control" \
        "Registered nodes: ${node_total}" \
        "dashboard"  "Node Dashboard — status overview" \
        "manage"     "Manage Nodes — select a node" \
        "bulk"       "Bulk Actions — start/stop/restart all" \
        "add-node"   "Add Node — interactive wizard" \
        "import"     "Import Inventory — from .inv file" \
        "firewall"   "Firewall — view/manage UFW rules" \
        "server"     "Server Info — system overview" \
        "exit"       "Exit")" || break

    case "$choice" in
        dashboard)
            "${SCRIPT_DIR}/node-list.sh" --view-only
            ;;
        manage)
            "${SCRIPT_DIR}/node-list.sh"
            ;;
        bulk)
            "${SCRIPT_DIR}/bulk-actions.sh"
            ;;
        add-node)
            "${SCRIPT_DIR}/../inventory/add-node.sh"
            ;;
        import)
            "${SCRIPT_DIR}/inventory-menu.sh"
            ;;
        firewall)
            source "${SCRIPT_DIR}/../lib/ufw-helpers.sh"
            tmpfile="$(mktemp)"
            list_managed_rules > "$tmpfile" 2>&1
            # Also show full UFW status
            echo "" >> "$tmpfile"
            echo "Full UFW Status:" >> "$tmpfile"
            echo "================" >> "$tmpfile"
            ufw status verbose >> "$tmpfile" 2>&1 || echo "(ufw not available)" >> "$tmpfile"
            cc_textbox "Firewall Rules" "$tmpfile"
            rm -f "$tmpfile"
            ;;
        server)
            "${SCRIPT_DIR}/server-info.sh"
            ;;
        exit)
            break
            ;;
    esac
done
