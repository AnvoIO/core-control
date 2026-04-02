#!/bin/bash

# =============================================================================
# core-control — Per-Node Actions (TUI)
# =============================================================================
# Action menu for a single node. Delegates to core-node scripts.
#
# Usage: node-actions.sh <CONTAINER_NAME>
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"
source "${SCRIPT_DIR}/../lib/ufw-helpers.sh"

require_whiptail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
CONTAINER_NAME="${1:-}"
if [[ -z "$CONTAINER_NAME" ]]; then
    log_error "Usage: $(basename "$0") <CONTAINER_NAME>"
    exit 1
fi

NODE_CONF="$(get_node_conf "$CONTAINER_NAME")"

# Read key info for display
NETWORK="$(get_node_value "$CONTAINER_NAME" "NETWORK" "?")"
NODE_ROLE="$(get_node_value "$CONTAINER_NAME" "NODE_ROLE" "?")"
STORAGE_PATH="$(get_node_value "$CONTAINER_NAME" "STORAGE_PATH" "?")"

# ---------------------------------------------------------------------------
# Action loop
# ---------------------------------------------------------------------------
while true; do
    # Check current container status
    local_status="STOPPED"
    if command -v docker &>/dev/null; then
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
            local_status="RUNNING"
        fi
    fi

    action="$(cc_menu "${CONTAINER_NAME}" \
        "Status: ${local_status} | ${NETWORK}/${NODE_ROLE}" \
        "status"      "Detailed status" \
        "start"       "Start node" \
        "stop"        "Graceful stop (30m timeout)" \
        "restart"     "Restart node" \
        "logs"        "View Docker logs (Ctrl-C to exit)" \
        "snapshot"    "Create snapshot + prune" \
        "healthcheck" "Run health check" \
        "edit"        "Edit node.conf" \
        "regenerate"  "Regenerate configs from node.conf" \
        "remove"      "Remove this node" \
        "back"        "Return to node list")" || break

    case "$action" in
        status)
            tmpfile="$(mktemp)"
            "${CORE_NODE_DIR}/scripts/node/status.sh" "$NODE_CONF" > "$tmpfile" 2>&1 || true
            cc_textbox "Status: ${CONTAINER_NAME}" "$tmpfile"
            rm -f "$tmpfile"
            ;;

        start)
            clear
            "${CORE_NODE_DIR}/scripts/node/start.sh" "$NODE_CONF" || true
            echo ""
            echo "Press Enter to continue..."
            read -r
            ;;

        stop)
            if cc_yesno "Stop Node" "Stop ${CONTAINER_NAME}?\n\nThis uses a 30-minute grace period for clean shutdown."; then
                clear
                "${CORE_NODE_DIR}/scripts/node/stop.sh" "$NODE_CONF" || true
                echo ""
                echo "Press Enter to continue..."
                read -r
            fi
            ;;

        restart)
            if cc_yesno "Restart Node" "Restart ${CONTAINER_NAME}?"; then
                clear
                "${CORE_NODE_DIR}/scripts/node/restart.sh" "$NODE_CONF" || true
                echo ""
                echo "Press Enter to continue..."
                read -r
            fi
            ;;

        logs)
            clear
            echo "Showing logs for ${CONTAINER_NAME} (Ctrl-C to exit)..."
            echo ""
            "${CORE_NODE_DIR}/scripts/node/logs.sh" "$NODE_CONF" -f -n 100 || true
            ;;

        snapshot)
            clear
            "${CORE_NODE_DIR}/scripts/snapshot/create.sh" "$NODE_CONF" --prune || true
            echo ""
            echo "Press Enter to continue..."
            read -r
            ;;

        healthcheck)
            tmpfile="$(mktemp)"
            "${CORE_NODE_DIR}/scripts/monitoring/health-check.sh" --once "$NODE_CONF" > "$tmpfile" 2>&1 || true
            cc_textbox "Health Check: ${CONTAINER_NAME}" "$tmpfile"
            rm -f "$tmpfile"
            ;;

        edit)
            "${EDITOR:-nano}" "$NODE_CONF"
            if cc_yesno "Regenerate" "Regenerate runtime configs from updated node.conf?"; then
                clear
                "${CORE_NODE_DIR}/scripts/setup/generate-config.sh" "$NODE_CONF" || true
                echo ""
                echo "Press Enter to continue..."
                read -r
            fi
            ;;

        regenerate)
            clear
            "${CORE_NODE_DIR}/scripts/setup/generate-config.sh" "$NODE_CONF" || true
            echo ""
            echo "Press Enter to continue..."
            read -r
            ;;

        remove)
            if cc_yesno "Remove Node" "Remove ${CONTAINER_NAME}?\n\nThis will stop the container and delete configs.\nNode data at ${STORAGE_PATH} will NOT be deleted."; then
                "${SCRIPT_DIR}/../inventory/remove-node.sh" "$CONTAINER_NAME" --force
                cc_msgbox "Removed" "Node ${CONTAINER_NAME} has been removed."
                break
            fi
            ;;

        back)
            break
            ;;
    esac
done
