#!/bin/bash

# =============================================================================
# core-control — Show Managed UFW Rules
# =============================================================================
# Displays all UFW rules managed by core-control.
#
# Usage: show-rules.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"
source "${SCRIPT_DIR}/../lib/ufw-helpers.sh"

list_managed_rules
