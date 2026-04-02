#!/bin/bash

# =============================================================================
# core-control — Inventory Menu (TUI)
# =============================================================================
# Import/export inventory files via whiptail menu.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"

require_whiptail

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
while true; do
    action="$(cc_menu "Inventory" \
        "Import or export node inventory:" \
        "import"   "Import — load nodes from .inv file" \
        "export"   "Export — save current nodes to .inv file" \
        "back"     "Return to main menu")" || break

    case "$action" in
        import)
            # Find .inv files in inventory directory
            local_inv_files=()
            while IFS= read -r -d '' f; do
                local_inv_files+=("$f" "$(basename "$f")")
            done < <(find "$INVENTORY_DIR" -name '*.inv' -print0 2>/dev/null | sort -z)

            if [[ ${#local_inv_files[@]} -gt 0 ]]; then
                local_inv_files+=("custom" "Enter a custom path")

                inv_file="$(cc_menu "Import Inventory" \
                    "Select an inventory file:" \
                    "${local_inv_files[@]}")" || continue

                if [[ "$inv_file" == "custom" ]]; then
                    inv_file="$(cc_inputbox "Import Inventory" \
                        "Path to .inv file:" "")" || continue
                fi
            else
                inv_file="$(cc_inputbox "Import Inventory" \
                    "No .inv files found in ${INVENTORY_DIR}/.\n\nEnter path to .inv file:" "")" || continue
            fi

            if [[ -z "$inv_file" ]]; then
                cc_msgbox "Error" "No file specified."
                continue
            fi

            if [[ ! -f "$inv_file" ]]; then
                cc_msgbox "Error" "File not found: ${inv_file}"
                continue
            fi

            # Run import
            clear
            "${SCRIPT_DIR}/../inventory/import.sh" "$inv_file" || true
            echo ""
            echo "Press Enter to continue..."
            read -r
            ;;

        export)
            default_path="${INVENTORY_DIR}/export-$(date '+%Y%m%d').inv"
            export_path="$(cc_inputbox "Export Inventory" \
                "Export to file:" "$default_path")" || continue

            if [[ -z "$export_path" ]]; then
                cc_msgbox "Error" "No file specified."
                continue
            fi

            "${SCRIPT_DIR}/../inventory/export.sh" "$export_path"
            cc_msgbox "Export Complete" "Exported to: ${export_path}"
            ;;

        back)
            break
            ;;
    esac
done
