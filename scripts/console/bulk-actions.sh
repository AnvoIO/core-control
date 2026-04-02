#!/bin/bash

# =============================================================================
# core-control — Bulk Actions
# =============================================================================
# Start/stop/restart all nodes, or show status for all.
#
# Usage:
#   bulk-actions.sh                  TUI menu
#   bulk-actions.sh status-all       CLI: show all statuses
#   bulk-actions.sh start-all        CLI: start all nodes
#   bulk-actions.sh stop-all         CLI: stop all nodes
#   bulk-actions.sh restart-all      CLI: restart all nodes
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"

# ---------------------------------------------------------------------------
# Status all — gather and display
# ---------------------------------------------------------------------------
do_status_all() {
    local output=""
    output+="$(printf '%-35s %-8s %-18s %s\n' 'CONTAINER' 'STATUS' 'NETWORK/ROLE' 'ENDPOINT')"
    output+=$'\n'
    output+="$(printf '%-35s %-8s %-18s %s\n' '---------' '------' '------------' '--------')"
    output+=$'\n'

    local statuses
    statuses="$(get_all_node_statuses)"

    if [[ -z "$statuses" ]]; then
        output+="(no nodes registered)"$'\n'
    else
        while IFS='|' read -r name status network role bind_ip http_port; do
            [[ -z "$name" ]] && continue
            local endpoint="${bind_ip}:${http_port:-n/a}"
            output+="$(printf '%-35s %-8s %-18s %s\n' "$name" "$status" "${network}/${role}" "$endpoint")"
            output+=$'\n'
        done <<< "$statuses"
    fi

    echo -n "$output"
}

# ---------------------------------------------------------------------------
# Start all
# ---------------------------------------------------------------------------
do_start_all() {
    local nodes
    nodes="$(list_all_nodes)"

    if [[ -z "$nodes" ]]; then
        log_info "No nodes registered."
        return 0
    fi

    log_header "Starting All Nodes"

    local count=0 total
    total="$(echo "$nodes" | wc -l)"

    local name
    for name in $nodes; do
        count=$((count + 1))
        log_info "[${count}/${total}] Starting ${name}..."
        local conf
        conf="$(get_node_conf "$name")" || continue
        "${CORE_NODE_DIR}/scripts/node/start.sh" "$conf" || \
            log_warn "Failed to start ${name}"
    done

    log_success "Start-all complete."
}

# ---------------------------------------------------------------------------
# Stop all
# ---------------------------------------------------------------------------
do_stop_all() {
    local nodes
    nodes="$(list_all_nodes)"

    if [[ -z "$nodes" ]]; then
        log_info "No nodes registered."
        return 0
    fi

    log_header "Stopping All Nodes"

    local count=0 total
    total="$(echo "$nodes" | wc -l)"

    local name
    for name in $nodes; do
        count=$((count + 1))
        log_info "[${count}/${total}] Stopping ${name}..."
        local conf
        conf="$(get_node_conf "$name")" || continue
        "${CORE_NODE_DIR}/scripts/node/stop.sh" "$conf" || \
            log_warn "Failed to stop ${name}"
    done

    log_success "Stop-all complete."
}

# ---------------------------------------------------------------------------
# Restart all
# ---------------------------------------------------------------------------
do_restart_all() {
    local nodes
    nodes="$(list_all_nodes)"

    if [[ -z "$nodes" ]]; then
        log_info "No nodes registered."
        return 0
    fi

    log_header "Restarting All Nodes"

    local count=0 total
    total="$(echo "$nodes" | wc -l)"

    local name
    for name in $nodes; do
        count=$((count + 1))
        log_info "[${count}/${total}] Restarting ${name}..."
        local conf
        conf="$(get_node_conf "$name")" || continue
        "${CORE_NODE_DIR}/scripts/node/restart.sh" "$conf" || \
            log_warn "Failed to restart ${name}"
    done

    log_success "Restart-all complete."
}

# ---------------------------------------------------------------------------
# CLI dispatch (non-interactive)
# ---------------------------------------------------------------------------
if [[ -n "${1:-}" ]]; then
    case "$1" in
        status-all)
            do_status_all
            ;;
        start-all)
            do_start_all
            ;;
        stop-all)
            do_stop_all
            ;;
        restart-all)
            do_restart_all
            ;;
        *)
            log_error "Unknown action: $1"
            exit 1
            ;;
    esac
    exit 0
fi

# ---------------------------------------------------------------------------
# TUI mode
# ---------------------------------------------------------------------------
require_whiptail

while true; do
    action="$(cc_menu "Bulk Actions" \
        "Actions for all registered nodes:" \
        "status"   "Status — show all node statuses" \
        "start"    "Start All — start every node" \
        "stop"     "Stop All — graceful stop (sequential)" \
        "restart"  "Restart All — stop then start each" \
        "back"     "Return to main menu")" || break

    case "$action" in
        status)
            tmpfile="$(mktemp)"
            do_status_all > "$tmpfile"
            cc_textbox "All Node Status" "$tmpfile"
            rm -f "$tmpfile"
            ;;

        start)
            if cc_yesno "Start All" "Start all registered nodes?"; then
                clear
                do_start_all
                echo ""
                echo "Press Enter to continue..."
                read -r
            fi
            ;;

        stop)
            if cc_yesno "Stop All" "Stop ALL nodes?\n\nEach node uses a 30-minute grace period.\nThis may take a long time."; then
                clear
                do_stop_all
                echo ""
                echo "Press Enter to continue..."
                read -r
            fi
            ;;

        restart)
            if cc_yesno "Restart All" "Restart all nodes sequentially?"; then
                clear
                do_restart_all
                echo ""
                echo "Press Enter to continue..."
                read -r
            fi
            ;;

        back)
            break
            ;;
    esac
done
