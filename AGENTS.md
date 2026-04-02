# AGENTS.md

Guidance for AI coding assistants working on this repository.

## Project Overview

**core-control** is a server provisioning and node management tool for [AnvoIO core-node](https://github.com/AnvoIO/core-node) blockchain deployments. It provisions bare Ubuntu servers as Docker hosts, manages UFW firewall rules for Docker, and provides an interactive TUI (whiptail) for managing multiple core-node instances.

core-control does NOT reimplement core-node functionality. It delegates all node operations (start, stop, status, snapshot, health-check, config generation) to core-node scripts by passing `node.conf` paths.

## Architecture

### Dependency on core-node

core-control sources core-node's shared libraries at runtime:
- `${CORE_NODE_DIR}/scripts/lib/common.sh` — logging, prompts, validators
- `${CORE_NODE_DIR}/scripts/lib/config-utils.sh` — node.conf read/write
- `${CORE_NODE_DIR}/scripts/lib/network-defaults.sh` — chain IDs, ports, roles, resources

The `CORE_NODE_DIR` path is set in `core-control.conf` (default: `/opt/core-node`).

### Configuration Flow

```
setup.sh          → provisions server, clones core-node, writes core-control.conf
import.sh <file>  → parses .inv → creates node.conf per node → generate-config.sh → UFW rules
add-node.sh       → whiptail wizard → creates node.conf → generate-config.sh → UFW rules
core-control      → TUI console → delegates to core-node scripts
```

### Data Layout

```
core-control.conf        — global config (CORE_NODE_DIR, DATA_ROOT, SSH_PORT)
nodes/<CONTAINER_NAME>/  — one dir per node, each containing node.conf (gitignored)
inventory/               — private .inv files for bulk import (gitignored)
```

Node data lives at `${DATA_ROOT}/libre/{network}/{producer_name}/` — managed by core-node, not core-control.

## Directory Layout

```
scripts/
├── lib/
│   ├── cc-common.sh      — TUI wrappers, inventory helpers, sources core-node libs
│   └── ufw-helpers.sh    — UFW rule apply/remove/list with core-control: comment tags
├── console/
│   ├── main-menu.sh      — Top-level TUI loop
│   ├── node-list.sh      — Node dashboard with status + per-node selection
│   ├── node-actions.sh   — Per-node action menu (start/stop/restart/logs/etc)
│   ├── bulk-actions.sh   — Start-all, stop-all, restart-all, status-all
│   ├── server-info.sh    — System overview (CPU, RAM, disk, Docker, UFW)
│   └── inventory-menu.sh — Import/export TUI
├── inventory/
│   ├── import.sh         — Parse .inv → create node.conf files → generate-config
│   ├── export.sh         — Export current nodes to .inv format
│   ├── add-node.sh       — Whiptail-based add-node wizard
│   ├── remove-node.sh    — Stop + remove node configs + UFW rules
│   └── validate.sh       — Validate .inv file format
└── firewall/
    ├── apply-rules.sh    — Apply UFW rules for one node
    ├── apply-all.sh      — Apply UFW rules for all nodes
    └── show-rules.sh     — Display core-control-managed rules
```

## Shared Libraries

### cc-common.sh

Sources core-node libraries plus provides:
- **TUI wrappers:** `cc_menu`, `cc_msgbox`, `cc_textbox`, `cc_yesno`, `cc_inputbox`, `cc_radiolist`
- **Inventory helpers:** `list_all_nodes`, `get_node_conf`, `get_node_value`, `get_all_node_statuses`, `create_node_conf`, `run_generate_config`, `load_peers`, `node_count`, `write_node_config`
- **Path constants:** `CC_DIR`, `NODES_DIR`, `INVENTORY_DIR`
- **Validation:** `require_whiptail`

### ufw-helpers.sh

- `apply_node_rules <node.conf>` — role-based UFW rules with `core-control:` comment tags
- `remove_node_rules <container_name>` — delete rules by comment
- `list_managed_rules` — show all core-control-tagged rules

## Common Patterns

### Script Header

```bash
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/cc-common.sh"
```

### Node Iteration

```bash
for name in $(list_all_nodes); do
    local conf
    conf="$(get_node_conf "$name")"
    # ... use conf with core-node scripts
done
```

### Delegating to core-node

```bash
"${CORE_NODE_DIR}/scripts/node/start.sh" "$conf_path"
"${CORE_NODE_DIR}/scripts/setup/generate-config.sh" "$conf_path"
```

### TUI Pattern

```bash
require_whiptail
choice="$(cc_menu "Title" "Prompt" "tag1" "desc1" "tag2" "desc2")" || break
```

## Inventory Format

Pipe-delimited `.inv` files:
```
# CONTAINER_NAME|NETWORK|NODE_ROLE|BIND_IP|HTTP_PORT|P2P_PORT|PRODUCER_NAME|SIGNATURE_PROVIDER|LOG_PROFILE|SNAPSHOT_INTERVAL|SNAPSHOT_RETENTION|MAX_RETAINED_BLOCK_FILES|BLOCKS_LOG_STRIDE
```

Fields after SIGNATURE_PROVIDER are optional (defaults applied). Comments start with `#`.

## UFW Rule Convention

All rules use `comment "core-control: <CONTAINER_NAME> <description>"` for identification. Rules by role:
- **producer:** HTTP localhost-only, NO public P2P (signing nodes connect outbound to peers)
- **seed:** P2P public (relay), no HTTP
- **API roles:** P2P public, HTTP public

## Key Design Decisions

- **No secrets in repo** — `inventory/` and `nodes/` are gitignored
- **Pipe-delimited inventory** — consistent with core-node's peers-*.conf format
- **whiptail TUI** — pre-installed on Ubuntu, sufficient for menus/input
- **Host networking** — standard `ufw allow` rules work (no need for ufw-docker per-container rules)
- **Sequential bulk operations** — 30min stop grace period makes parallel stops risky
- **No config duplication** — core-control creates node.conf, delegates everything else to core-node

## Known Constraints

- All scripts must pass `bash -n` syntax validation
- `cc-common.sh` must not overwrite caller's `CONFIG_FILE` (use `get_node_value` for quick reads)
- whiptail menu items are pairs: tag + description
- whiptail radiolist items are triples: tag + description + ON/OFF
