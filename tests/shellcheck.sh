#!/bin/bash
set -euo pipefail

# =============================================================================
# core-control — ShellCheck Linter
# =============================================================================
# Runs shellcheck on all shell scripts in the project.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAILURES=$((FAILURES + 1)); }
info() { echo -e "  ${YELLOW}INFO${NC} $1"; }

FAILURES=0

echo ""
echo "========================================="
echo "  ShellCheck Linter"
echo "========================================="
echo ""

# Check shellcheck is available
if ! command -v shellcheck &>/dev/null; then
    info "shellcheck not installed — skipping."
    info "Install with: sudo apt-get install shellcheck"
    exit 0
fi

info "ShellCheck version: $(shellcheck --version | head -2 | tail -1)"
echo ""

# Find all shell scripts
mapfile -t scripts < <(find "$PROJECT_DIR" -name '*.sh' -not -path '*/.git/*' -not -path '*/node_modules/*' | sort)

# Also include the core-control entry point (no .sh extension)
scripts+=("${PROJECT_DIR}/core-control")

# Excluded warnings:
# SC1091: Not following sourced files (we source cross-project)
# SC1090: Can't follow non-constant source
# SC2034: Variable appears unused (many are used by sourced scripts)
# SC2154: Variable referenced but not assigned (set by sourced libs)
EXCLUDES="SC1091,SC1090,SC2034,SC2154"

for script in "${scripts[@]}"; do
    [[ -f "$script" ]] || continue
    rel_path="${script#${PROJECT_DIR}/}"

    if shellcheck -x -e "$EXCLUDES" -S warning "$script" 2>&1; then
        pass "$rel_path"
    else
        fail "$rel_path"
    fi
done

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "========================================="
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}All scripts pass ShellCheck${NC}"
else
    echo -e "${RED}${FAILURES} script(s) have warnings${NC}"
fi
echo "========================================="
exit "$FAILURES"
