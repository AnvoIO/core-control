#!/bin/bash

# =============================================================================
# core-control — Add Node (Whiptail Wizard)
# =============================================================================
# Interactive wizard to add a single node. Creates node.conf, runs
# generate-config, applies UFW rules, and optionally starts the node.
#
# Usage: add-node.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"
source "${SCRIPT_DIR}/../lib/ufw-helpers.sh"

require_whiptail

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {

# ---------------------------------------------------------------------------
# Collect node configuration via whiptail
# ---------------------------------------------------------------------------

# Network
network="$(cc_radiolist "Add Node" "Select network:" \
    "testnet"  "Libre Testnet" "ON" \
    "mainnet"  "Libre Mainnet" "OFF")" || exit 0

# Role
node_role="$(cc_radiolist "Add Node" "Select node role:" \
    "producer"     "Block producer"          "ON" \
    "seed"         "P2P relay (no HTTP API)" "OFF" \
    "light-api"    "API with partial history" "OFF" \
    "full-api"     "Full API + state history" "OFF" \
    "full-history" "Full history + traces"    "OFF")" || exit 0

# Producer-specific fields
producer_name=""
sig_provider=""
if [[ "$node_role" == "producer" ]]; then
    producer_name="$(cc_inputbox "Add Node" "Producer name (on-chain account):" "")" || exit 0
    if [[ -z "$producer_name" ]]; then
        cc_msgbox "Error" "Producer name is required."
        exit 1
    fi

    sig_provider="$(cc_inputbox "Add Node" \
        "Signature provider (PUB_KEY=KEY:PRIV_KEY):" "")" || exit 0
    if [[ -z "$sig_provider" ]]; then
        cc_msgbox "Error" "Signature provider is required for producer role."
        exit 1
    fi
fi

# Container name
default_name="libre-${network}-${producer_name:-$node_role}"
container_name="$(cc_inputbox "Add Node" "Container name:" "$default_name")" || exit 0

if [[ -z "$container_name" ]]; then
    cc_msgbox "Error" "Container name is required."
    exit 1
fi

# Check for existing node
if [[ -d "${NODES_DIR}/${container_name}" ]]; then
    cc_msgbox "Error" "Node '${container_name}' already exists."
    exit 1
fi

# Bind IP — detect interfaces and let user choose
bind_ip="0.0.0.0"
if command -v ip &>/dev/null; then
    local_ifs="$(detect_interfaces)"
    if [[ -n "$local_ifs" ]]; then
        # Build radiolist items from detected interfaces
        local -a radio_items=()
        local first=true
        while IFS='|' read -r iface addr; do
            if $first; then
                radio_items+=("$addr" "${iface}" "ON")
                first=false
            else
                radio_items+=("$addr" "${iface}" "OFF")
            fi
        done <<< "$local_ifs"
        radio_items+=("0.0.0.0" "All interfaces" "OFF")

        bind_ip="$(cc_radiolist "Add Node" "Select bind IP:" \
            "${radio_items[@]}")" || exit 0
    fi
fi

# Ports — defaults from network-defaults.sh
eval "$(get_default_ports "$network")"
# HTTP_PORT, P2P_PORT, SHIP_PORT are now set

if [[ "$node_role" != "seed" ]]; then
    HTTP_PORT="$(cc_inputbox "Add Node" "HTTP API port:" "$HTTP_PORT")" || exit 0
fi
P2P_PORT="$(cc_inputbox "Add Node" "P2P port:" "$P2P_PORT")" || exit 0

# SHiP port (full-api and full-history only)
local ship_port=""
if [[ "$node_role" == "full-api" || "$node_role" == "full-history" ]]; then
    ship_port="$(cc_inputbox "Add Node" "State History (SHiP) port:" "${SHIP_PORT:-}")" || exit 0
fi

# Storage path
default_storage="${DATA_ROOT}/libre/${network}/${producer_name:-$container_name}"
storage_path="$(cc_inputbox "Add Node" "Storage path:" "$default_storage")" || exit 0

# Log profile
log_profile="$(cc_radiolist "Add Node" "Log profile:" \
    "standard"   "Normal operation (INFO)"    "ON" \
    "production" "Production (WARN only)"     "OFF" \
    "debug"      "Troubleshooting (verbose)"  "OFF" \
    "minimal"    "Resource-constrained (ERR)" "OFF")" || exit 0

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
summary="Container:  ${container_name}
Network:    ${network}
Role:       ${node_role}
Bind IP:    ${bind_ip}
HTTP Port:  ${HTTP_PORT:-n/a}
P2P Port:   ${P2P_PORT}
Storage:    ${storage_path}
Log:        ${log_profile}"

if [[ -n "$producer_name" ]]; then
    summary+="
Producer:   ${producer_name}"
fi

if ! cc_yesno "Confirm" "$summary

Create this node?"; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Create node.conf
# ---------------------------------------------------------------------------
log_info "Creating node configuration..."

conf_path="$(create_node_conf "$container_name")"

write_node_config \
    "$container_name" \
    "$network" \
    "$node_role" \
    "$bind_ip" \
    "${HTTP_PORT:-}" \
    "$P2P_PORT" \
    "$ship_port" \
    "$storage_path" \
    "$log_profile" \
    "100000" \
    "10" \
    "100000" \
    "10" \
    "$producer_name" \
    "$sig_provider"

# ---------------------------------------------------------------------------
# Generate configs
# ---------------------------------------------------------------------------
log_info "Generating runtime configuration..."
"${CORE_NODE_DIR}/scripts/setup/generate-config.sh" "$conf_path"

# ---------------------------------------------------------------------------
# Apply firewall rules
# ---------------------------------------------------------------------------
apply_node_rules "$conf_path" || true

# ---------------------------------------------------------------------------
# Offer to start
# ---------------------------------------------------------------------------
log_success "Node '${container_name}' created."

if cc_yesno "Start Node" "Start ${container_name} now?"; then
    "${CORE_NODE_DIR}/scripts/node/start.sh" "$conf_path"
fi
}

main
