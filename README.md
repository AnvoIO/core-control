# core-control

Server provisioning and node management tool for [AnvoIO core-node](https://github.com/AnvoIO/core-node) blockchain deployments.

Provisions a bare Ubuntu server as a Docker host with properly configured UFW firewall, then provides an interactive TUI console for managing multiple core-node instances.

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/AnvoIO/core-control.git /opt/core-control
cd /opt/core-control

# 2. Provision the server (installs Docker, UFW, core-node, tunes system)
sudo ./setup.sh

# 3. Import nodes from an inventory file
core-control import inventory/my-nodes.inv

# 4. Launch the console
core-control
```

## What setup.sh Does

1. Installs system packages (jq, zstd, whiptail, btrfs-progs, etc.)
2. Installs Docker Engine + Compose plugin from the official Docker repository
3. Configures UFW firewall + [ufw-docker](https://github.com/chaifeng/ufw-docker) to prevent Docker from bypassing UFW
4. Clones [core-node](https://github.com/AnvoIO/core-node) to `/opt/core-node`
5. Creates data directories (`/data/libre/{mainnet,testnet}/`)
6. Tunes system settings (vm.max_map_count, file limits)

Options:
```
sudo ./setup.sh --core-node-dir /opt/core-node --data-root /data --ssh-port 22
```

## Node Management

### Interactive Console (TUI)

```bash
core-control
```

Provides a whiptail-based menu for:
- **Node Dashboard** — status overview of all nodes
- **Manage Nodes** — per-node actions (start/stop/restart/logs/snapshot/health-check)
- **Bulk Actions** — start-all, stop-all, restart-all
- **Add Node** — interactive wizard
- **Import Inventory** — bulk import from .inv file
- **Firewall** — view/manage UFW rules
- **Server Info** — system overview

### CLI Commands

```bash
core-control status            # Show all node statuses
core-control start-all         # Start all nodes
core-control stop-all          # Stop all nodes (sequential, 30m grace each)
core-control restart-all       # Restart all nodes
core-control import <file>     # Import nodes from .inv file
core-control export [file]     # Export nodes to .inv format
core-control add-node          # Interactive add-node wizard
core-control remove-node <n>   # Remove a node
core-control firewall          # Show managed UFW rules
```

## Inventory Format

Nodes are defined in pipe-delimited `.inv` files. Place them in `inventory/` (gitignored — contains private keys).

```
# CONTAINER_NAME|NETWORK|NODE_ROLE|BIND_IP|HTTP_PORT|P2P_PORT|PRODUCER_NAME|SIGNATURE_PROVIDER|LOG_PROFILE|SNAPSHOT_INTERVAL|SNAPSHOT_RETENTION|MAX_RETAINED_BLOCK_FILES|BLOCKS_LOG_STRIDE
libre-testnet-potato1|testnet|producer|10.10.10.181|8881|9871|potato1|PUB_K1_xxx=KEY:PVT_K1_xxx|||
libre-mainnet-cryptobloks|mainnet|producer|10.10.10.182|8880|9870|cryptobloks|PUB_K1_yyy=KEY:PVT_K1_yyy|standard|100000|10|10|100000
```

**Fields:**
| # | Field | Required | Default |
|---|-------|----------|---------|
| 1 | CONTAINER_NAME | Yes | — |
| 2 | NETWORK | Yes | — |
| 3 | NODE_ROLE | Yes | — |
| 4 | BIND_IP | Yes | — |
| 5 | HTTP_PORT | Yes (except seed) | — |
| 6 | P2P_PORT | Yes | — |
| 7 | PRODUCER_NAME | Yes (producer role) | — |
| 8 | SIGNATURE_PROVIDER | Yes (producer role) | — |
| 9 | LOG_PROFILE | No | standard |
| 10 | SNAPSHOT_INTERVAL | No | 100000 |
| 11 | SNAPSHOT_RETENTION | No | 10 |
| 12 | MAX_RETAINED_BLOCK_FILES | No | 10 |
| 13 | BLOCKS_LOG_STRIDE | No | 100000 |

Import auto-derives: CORE_VERSION, STORAGE_PATH, STATE_IN_MEMORY, resource tuning (per role), peers (from core-node), and disabled optional features.

## Firewall

UFW rules are applied per-node based on role:
- **P2P ports**: Always public (blockchain peering)
- **HTTP API (producer)**: Localhost only (producer_api_plugin is sensitive)
- **HTTP API (API roles)**: Public
- **Seed nodes**: P2P only (no HTTP)

All managed rules are tagged with `core-control:` comments for identification. View with:
```bash
core-control firewall
```

## Configuration

`core-control.conf` is the global config (written by setup.sh):

```
CORE_NODE_DIR=/opt/core-node    # Path to core-node repo
DATA_ROOT=/data                  # Root data directory
SSH_PORT=22                      # SSH port for UFW
```

Node configs live in `nodes/<CONTAINER_NAME>/node.conf` (gitignored). These are standard core-node `node.conf` files — same format used by the wizard and all core-node scripts.

## Prerequisites

- Ubuntu 22.04 or 24.04
- Root access (for setup.sh)
- BTRFS filesystem recommended for `/data` (required for backup snapshots)
