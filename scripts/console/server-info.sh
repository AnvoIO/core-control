#!/bin/bash

# =============================================================================
# core-control — Server Info (TUI)
# =============================================================================
# Displays system overview: CPU, RAM, disk, Docker, UFW status.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"

require_whiptail

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local tmpfile
    tmpfile="$(mktemp)"

    {
        echo "Server Information"
        echo "=================="
        echo ""

        # Hostname
        echo "Hostname:     $(hostname)"
        echo "OS:           $(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo 'unknown')"
        echo "Kernel:       $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo ""

        # CPU
        echo "CPU"
        echo "---"
        local cpu_model cpu_cores
        cpu_model="$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo 'unknown')"
        cpu_cores="$(nproc 2>/dev/null || echo '?')"
        echo "  Model:  ${cpu_model}"
        echo "  Cores:  ${cpu_cores}"
        echo "  Load:   $(uptime | awk -F'load average:' '{print $2}' | xargs)"
        echo ""

        # Memory
        echo "Memory"
        echo "------"
        free -h | awk '
            /^Mem:/ { printf "  Total: %s  Used: %s  Free: %s  Available: %s\n", $2, $3, $4, $7 }
            /^Swap:/ { printf "  Swap:  %s  Used: %s  Free: %s\n", $2, $3, $4 }
        '
        echo ""

        # Disk
        echo "Disk"
        echo "----"
        df -hT "$DATA_ROOT" 2>/dev/null | awk '
            NR==1 { printf "  %-20s %6s %6s %6s %5s %s\n", "Filesystem", "Type", "Size", "Used", "Use%", "Mount" }
            NR==2 { printf "  %-20s %6s %6s %6s %5s %s\n", $1, $2, $3, $4, $6, $7 }
        '
        echo ""

        # Docker
        echo "Docker"
        echo "------"
        if command -v docker &>/dev/null; then
            echo "  Version:    $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
            echo "  Compose:    $(docker compose version 2>/dev/null | awk '{print $NF}')"
            local running_count total_count
            running_count="$(docker ps -q 2>/dev/null | wc -l)"
            total_count="$(docker ps -aq 2>/dev/null | wc -l)"
            echo "  Containers: ${running_count} running / ${total_count} total"
            local images_count
            images_count="$(docker images -q 2>/dev/null | wc -l)"
            echo "  Images:     ${images_count}"
        else
            echo "  (not installed)"
        fi
        echo ""

        # UFW
        echo "UFW Firewall"
        echo "------------"
        if command -v ufw &>/dev/null; then
            echo "  $(ufw status 2>/dev/null | head -1)"
            local managed_rules
            managed_rules="$(ufw status 2>/dev/null | grep -c 'core-control:' || echo 0)"
            echo "  Managed rules: ${managed_rules}"
        else
            echo "  (not installed)"
        fi
        echo ""

        # core-control
        echo "core-control"
        echo "------------"
        echo "  Core-node:  ${CORE_NODE_DIR}"
        echo "  Data root:  ${DATA_ROOT}"
        echo "  Nodes dir:  ${NODES_DIR}"
        echo "  Nodes:      $(node_count) registered"
        echo ""

        # Uptime
        echo "Uptime: $(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1, $2}')"

    } > "$tmpfile" 2>&1

    cc_textbox "Server Info" "$tmpfile"
    rm -f "$tmpfile"
}

main
