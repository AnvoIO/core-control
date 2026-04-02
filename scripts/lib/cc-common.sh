#!/bin/bash

# =============================================================================
# core-control — Shared Library
# =============================================================================
# Bridge to core-node libraries plus TUI wrappers and inventory helpers.
#
# Source this file from other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/cc-common.sh"
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Source guard
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

if [[ "${_CC_COMMON_SH_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_CC_COMMON_SH_LOADED="true"

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
_CC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_DIR="$(cd "${_CC_LIB_DIR}/../.." && pwd)"

# ---------------------------------------------------------------------------
# Load core-control config
# ---------------------------------------------------------------------------
if [[ ! -f "${CC_DIR}/core-control.conf" ]]; then
    echo "ERROR: core-control.conf not found at ${CC_DIR}/core-control.conf" >&2
    echo "Run setup.sh first." >&2
    exit 1
fi
source "${CC_DIR}/core-control.conf"

# Derived paths
NODES_DIR="${CC_DIR}/nodes"
INVENTORY_DIR="${CC_DIR}/inventory"

# ---------------------------------------------------------------------------
# Load core-node libraries
# ---------------------------------------------------------------------------
if [[ ! -d "$CORE_NODE_DIR" ]]; then
    echo "ERROR: core-node not found at ${CORE_NODE_DIR}" >&2
    echo "Run setup.sh or set CORE_NODE_DIR in core-control.conf." >&2
    exit 1
fi

source "${CORE_NODE_DIR}/scripts/lib/common.sh"
source "${CORE_NODE_DIR}/scripts/lib/config-utils.sh"
source "${CORE_NODE_DIR}/scripts/lib/network-defaults.sh"

# ---------------------------------------------------------------------------
# Whiptail TUI wrappers
# ---------------------------------------------------------------------------

# Detect terminal size for whiptail
cc_term_height() { tput lines 2>/dev/null || echo 24; }
cc_term_width()  { tput cols  2>/dev/null || echo 80; }

# cc_menu "title" "prompt" "tag1" "description1" "tag2" "description2" ...
# Returns selected tag on stdout.
cc_menu() {
    local title="$1" prompt="$2"
    shift 2

    local items=("$@")
    local count=$(( ${#items[@]} / 2 ))
    local height=$(( count + 8 ))
    local term_h
    term_h="$(cc_term_height)"
    (( height > term_h - 2 )) && height=$(( term_h - 2 ))

    local width
    width="$(cc_term_width)"
    (( width > 76 )) && width=76

    whiptail --title "$title" --menu "$prompt" \
        "$height" "$width" "$count" "${items[@]}" \
        3>&1 1>&2 2>&3
}

# cc_msgbox "title" "message"
cc_msgbox() {
    local height=12 width
    width="$(cc_term_width)"
    (( width > 76 )) && width=76
    whiptail --title "$1" --msgbox "$2" "$height" "$width"
}

# cc_textbox "title" "file_path"
# Displays file contents in a scrollable box.
cc_textbox() {
    local height width
    height="$(cc_term_height)"
    width="$(cc_term_width)"
    (( height > 2 )) && height=$(( height - 2 ))
    (( width > 76 )) && width=76
    whiptail --title "$1" --scrolltext --textbox "$2" "$height" "$width"
}

# cc_yesno "title" "question" — returns 0=yes, 1=no
cc_yesno() {
    local width
    width="$(cc_term_width)"
    (( width > 76 )) && width=76
    whiptail --title "$1" --yesno "$2" 10 "$width"
}

# cc_inputbox "title" "prompt" "default" — returns input on stdout
cc_inputbox() {
    local width
    width="$(cc_term_width)"
    (( width > 76 )) && width=76
    whiptail --title "$1" --inputbox "$2" 10 "$width" "${3:-}" \
        3>&1 1>&2 2>&3
}

# cc_radiolist "title" "prompt" "tag1" "desc1" "ON/OFF" "tag2" "desc2" "ON/OFF" ...
# Returns selected tag on stdout.
cc_radiolist() {
    local title="$1" prompt="$2"
    shift 2

    local items=("$@")
    local count=$(( ${#items[@]} / 3 ))
    local height=$(( count + 8 ))
    local term_h
    term_h="$(cc_term_height)"
    (( height > term_h - 2 )) && height=$(( term_h - 2 ))

    local width
    width="$(cc_term_width)"
    (( width > 76 )) && width=76

    whiptail --title "$title" --radiolist "$prompt" \
        "$height" "$width" "$count" "${items[@]}" \
        3>&1 1>&2 2>&3
}

# ---------------------------------------------------------------------------
# Require whiptail
# ---------------------------------------------------------------------------
require_whiptail() {
    if ! command -v whiptail &>/dev/null; then
        log_error "whiptail is required for the TUI console."
        log_info "Install with: sudo apt-get install whiptail"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Inventory helpers
# ---------------------------------------------------------------------------

# list_all_nodes — outputs CONTAINER_NAME for each registered node, sorted
list_all_nodes() {
    local dir
    for dir in "${NODES_DIR}"/*/; do
        [[ -d "$dir" && -f "${dir}node.conf" ]] || continue
        basename "$dir"
    done | sort
}

# get_node_conf "CONTAINER_NAME" — outputs absolute path to node.conf
get_node_conf() {
    local name="$1"
    local path="${NODES_DIR}/${name}/node.conf"
    if [[ ! -f "$path" ]]; then
        log_error "Node config not found: ${path}"
        return 1
    fi
    echo "$path"
}

# get_node_value "CONTAINER_NAME" "KEY" "default"
# Quick read of a single key from a node's config without changing global CONFIG_FILE.
get_node_value() {
    local name="$1" key="$2" default="${3:-}"
    local conf="${NODES_DIR}/${name}/node.conf"
    if [[ ! -f "$conf" ]]; then
        echo "$default"
        return 0
    fi
    local val
    val="$(grep "^${key}=" "$conf" 2>/dev/null | tail -n1 | cut -d'=' -f2-)"
    echo "${val:-$default}"
}

# get_all_node_statuses — outputs "CONTAINER_NAME|STATUS|NETWORK|ROLE|BIND_IP|HTTP_PORT"
# STATUS is RUNNING or STOPPED. Uses a single docker ps call for efficiency.
get_all_node_statuses() {
    local running_containers=""
    if command -v docker &>/dev/null; then
        running_containers="$(docker ps --format '{{.Names}}' 2>/dev/null || true)"
    fi

    local name
    for name in $(list_all_nodes); do
        local status="STOPPED"
        if echo "$running_containers" | grep -q "^${name}$"; then
            status="RUNNING"
        fi

        local network role bind_ip http_port
        network="$(get_node_value "$name" "NETWORK" "?")"
        role="$(get_node_value "$name" "NODE_ROLE" "?")"
        bind_ip="$(get_node_value "$name" "BIND_IP" "?")"
        http_port="$(get_node_value "$name" "HTTP_PORT" "?")"

        echo "${name}|${status}|${network}|${role}|${bind_ip}|${http_port}"
    done
}

# create_node_conf "CONTAINER_NAME" — creates node dir and empty node.conf, echoes path
# Note: new_config sets global CONFIG_FILE. When called via $(), CONFIG_FILE
# is set in the subshell only. Callers using $() must load_config the
# returned path before calling set_config/write_node_config.
create_node_conf() {
    local name="$1"
    local dir="${NODES_DIR}/${name}"
    mkdir -p "$dir"
    new_config "${dir}/node.conf" >&2
    echo "${dir}/node.conf"
}

# run_generate_config "CONTAINER_NAME" — runs core-node's generate-config.sh
run_generate_config() {
    local name="$1"
    local conf_path
    conf_path="$(get_node_conf "$name")"
    "${CORE_NODE_DIR}/scripts/setup/generate-config.sh" "$conf_path"
}

# load_peers "network" — reads core-node's peers file, returns comma-separated list
load_peers() {
    local network="$1"
    local peers_file="${CORE_NODE_DIR}/config/peers-${network}.conf"
    if [[ ! -f "$peers_file" ]]; then
        log_warn "Peers file not found: ${peers_file}"
        echo ""
        return 0
    fi

    local peers=""
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        local addr
        addr="$(echo "$line" | cut -d'|' -f2)"
        if [[ -n "$addr" ]]; then
            if [[ -n "$peers" ]]; then
                peers="${peers},${addr}"
            else
                peers="$addr"
            fi
        fi
    done < "$peers_file"
    echo "$peers"
}

# node_count — returns number of registered nodes
node_count() {
    list_all_nodes | wc -l
}

# ---------------------------------------------------------------------------
# write_node_config — populate a node.conf with all required keys
# ---------------------------------------------------------------------------
# Call create_node_conf first to set CONFIG_FILE, then call this function.
# Arguments are passed as KEY=VALUE environment-style variables:
#   write_node_config container_name network node_role bind_ip http_port \
#       p2p_port storage_path log_profile snapshot_interval snapshot_retention \
#       blocks_log_stride max_retained_block_files \
#       [producer_name] [sig_provider]
#
# Reads resource defaults and peers automatically from core-node.
write_node_config() {
    local wn_container_name="$1"
    local wn_network="$2"
    local wn_node_role="$3"
    local wn_bind_ip="$4"
    local wn_http_port="$5"
    local wn_p2p_port="$6"
    local wn_storage_path="$7"
    local wn_log_profile="${8:-standard}"
    local wn_snapshot_interval="${9:-100000}"
    local wn_snapshot_retention="${10:-10}"
    local wn_blocks_log_stride="${11:-100000}"
    local wn_max_retained="${12:-10}"
    local wn_producer_name="${13:-}"
    local wn_sig_provider="${14:-}"

    # Ensure CONFIG_FILE is loaded (create_node_conf via $() loses it)
    local wn_conf_path="${NODES_DIR}/${wn_container_name}/node.conf"
    if [[ -z "${CONFIG_FILE:-}" || "$CONFIG_FILE" != "$wn_conf_path" ]]; then
        load_config "$wn_conf_path"
    fi

    # Get resource defaults for this role
    local wn_resources
    wn_resources="$(get_default_resources "$wn_node_role")"

    local wn_chain_state_db_size wn_chain_threads wn_http_threads
    local wn_net_threads wn_max_clients wn_max_tx_time
    wn_chain_state_db_size="$(echo "$wn_resources" | grep CHAIN_STATE_DB_SIZE | cut -d= -f2)"
    wn_chain_threads="$(echo "$wn_resources" | grep CHAIN_THREADS | cut -d= -f2)"
    wn_http_threads="$(echo "$wn_resources" | grep HTTP_THREADS | cut -d= -f2)"
    wn_net_threads="$(echo "$wn_resources" | grep NET_THREADS | cut -d= -f2)"
    wn_max_clients="$(echo "$wn_resources" | grep MAX_CLIENTS | cut -d= -f2)"
    wn_max_tx_time="$(echo "$wn_resources" | grep MAX_TRANSACTION_TIME | cut -d= -f2)"

    # Load peers for this network
    local wn_peers
    wn_peers="$(load_peers "$wn_network")"

    # Core settings
    set_config "CONTAINER_NAME" "$wn_container_name"
    set_config "NETWORK" "$wn_network"
    set_config "NODE_ROLE" "$wn_node_role"
    set_config "CORE_VERSION" "$RECOMMENDED_CORE_VERSION"
    set_config "BIND_IP" "$wn_bind_ip"
    set_config "HTTP_PORT" "$wn_http_port"
    set_config "P2P_PORT" "$wn_p2p_port"
    set_config "STORAGE_PATH" "$wn_storage_path"
    set_config "STATE_IN_MEMORY" "true"
    set_config "LOG_PROFILE" "$wn_log_profile"
    set_config "AGENT_NAME" "Core ${wn_network} ${wn_node_role}"
    set_config "RESTART_POLICY" "unless-stopped"
    set_config "SNAPSHOT_INTERVAL" "$wn_snapshot_interval"
    set_config "SNAPSHOT_RETENTION" "$wn_snapshot_retention"
    set_config "BLOCKS_LOG_STRIDE" "$wn_blocks_log_stride"
    set_config "MAX_RETAINED_BLOCK_FILES" "$wn_max_retained"

    # Resource tuning
    set_config "CHAIN_STATE_DB_SIZE" "$wn_chain_state_db_size"
    set_config "CHAIN_THREADS" "$wn_chain_threads"
    set_config "HTTP_THREADS" "$wn_http_threads"
    set_config "NET_THREADS" "$wn_net_threads"
    set_config "MAX_CLIENTS" "$wn_max_clients"
    set_config "MAX_TRANSACTION_TIME" "$wn_max_tx_time"

    # Peers
    if [[ -n "$wn_peers" ]]; then
        set_config "PEERS" "$wn_peers"
    fi

    # Producer-specific
    if [[ "$wn_node_role" == "producer" && -n "$wn_producer_name" ]]; then
        set_config "PRODUCER_NAME" "$wn_producer_name"
        if [[ -n "$wn_sig_provider" ]]; then
            set_config "SIGNATURE_PROVIDER" "$wn_sig_provider"
        fi
    fi

    # Disabled features (can be enabled later via edit)
    set_config "API_GATEWAY_ENABLED" "false"
    set_config "FIREWALL_ENABLED" "true"
    set_config "WEBHOOK_ENABLED" "false"
    set_config "PROMETHEUS_ENABLED" "false"
    set_config "S3_ENABLED" "false"
}
