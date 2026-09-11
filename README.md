# Ghost

**Bare minimum Docker host that runs entirely in RAM with explicit persistence.**

The OS lives in a 3GB tmpfs. The Nix store and a small whitelist of persistent
state live on a compressed btrfs disk. Everything else is rebuilt from source on
every boot. There is no on-disk swap — zRAM keeps sensitive data out of
persistent storage entirely.

```
┌─────────────── RAM ───────────────────┐
│  /          tmpfs 3G (ephemeral)      │
│  /tmp       tmpfs (ephemeral)         │
│  zRAM       compressed swap (zstd)    │
├─────────────── Disk ──────────────────┤
│  /nix       btrfs subvol (immutable)  │
│  /persistent btrfs subvol (whitelist) │
│  /boot      EFI system partition      │
└───────────────────────────────────────┘
```

---

## Prerequisites

Ghost is built with [Nix](https://nixos.org). If you're on Ubuntu or Debian,
install it first:

```bash
# Install Nix (multi-user daemon mode — recommended)
sh <(curl -L https://nixos.org/nix/install) --daemon
```

Log out and back in (or open a new terminal), then enable flakes:

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

Verify it works:

```bash
nix --version
```

> **Note:** You do NOT need NixOS on your dev machine. Nix runs on any Linux
> distro. NixOS is only needed on the Ghost target hardware itself.

---

## Quick Start

```bash
# Enter the dev shell
nix develop

# Build locally (verify config compiles)
just test

# Run the VM integration test (proves persistence survives reboot)
just check-vm

# Deploy to hardware (see docs/deploying.md for the full workflow)
just deploy target=root@<ip>
```

## System Configurations

| Configuration | Purpose |
|---|---|
| `ghost` | Primary Docker host — tmpfs root, btrfs persistence |
| `ghost-fs` | Storage host — 3 data disks, SeaweedFS |
| `ghost-netboot` | PXE/netboot variant — runs entirely in RAM, no disk |
| `ghost-iso` | Bootable ISO installer |

## Commands

```
just              # Show all available commands
```

### Build & Test

| Command | What it does |
|---|---|
| `just test` | Build the system closure locally (catches eval errors) |
| `just check` | Run `nix flake check` (evaluates all outputs) |
| `just check-vm` | Boot a VM, verify tmpfs + persistence survives reboot |
| `just verify-host root@<ip>` | SSH into a live host and validate disk config |
| `just verify-host root@<ip> --reboot` | Same, but also reboots to prove persistence |

### Deploy

| Command | What it does |
|---|---|
| `just deploy target=root@<ip>` | `nixos-rebuild switch` to a running host |
| `just anywhere target=root@<ip>` | Fresh install via `nixos-anywhere` (formats disk) |
| `just netboot` | Start PXE server for netbooting |
| `just build-iso` | Build a bootable ISO |
| `just flash-usb device=/dev/sdX` | Write ISO to USB drive |

### Infrastructure

| Command | What it does |
|---|---|
| `just gcp-init` | Initialize OpenTofu with remote state |
| `just gcp-plan` | Plan GCP infrastructure changes |
| `just gcp-apply` | Apply planned changes |
| `just gcp-destroy` | Tear down all GCP infrastructure |

## Project Structure

```
flake.nix               Flake definition — all configs, checks, packages
hardware.nix             Boot chain, tmpfs root, btrfs mounts, CPU/firmware
disko.nix                Declarative disk partitioning (GPT + ESP + btrfs)

modules/nixos/
├── core.nix             zRAM, SSH, IPMI, base packages, state version
├── persistence.nix      Preservation whitelist (what survives reboot)
├── networking.nix       Firewall, Tailscale, Avahi
├── docker.nix           Docker daemon, metrics, auto-prune
├── grist.nix            Grist spreadsheet container
├── monitoring.nix       Prometheus Node Exporter
├── netboot.nix          PXE netboot overrides
└── seaweedfs.nix        SeaweedFS distributed storage

hosts/
└── ghost-fs.nix         Storage host config (3 data disks)

tests/
└── persistence.nix      NixOS VM integration test

scripts/
└── verify-host.sh       Remote host verification via SSH

docs/
├── architecture.md      Full system design, security model, attack surface
├── deploying.md         Three-stage deploy workflow (dry-activate → test → switch)
└── drive-config.md      Disk layout, btrfs subvolumes, partition details
```

## What Persists Across Reboots

Everything **not** on this list is wiped on reboot:

| Path | Purpose |
|---|---|
| `/var/lib/docker` | Container images, volumes, state |
| `/var/lib/grist` | Grist application data + secrets env file |
| `/var/lib/tailscale` | Tailscale identity & WireGuard keys |
| `/var/lib/nixos` | NixOS generated UID/GID mappings |
| `/var/lib/systemd` | Journal, timers |
| `/var/lib/portainer` | Portainer state |
| `/var/log` | System logs |
| `/etc/ssh` | SSH host keys (mounted in initrd) |
| `/etc/machine-id` | Stable machine identifier (mounted in initrd) |
| `/etc/NetworkManager/system-connections` | Saved network profiles |
| `/opt` | Optional software |

## Security Model

Ghost's architecture provides these security properties by default:

- **Reboot = reset** — filesystem-level compromises don't survive a power cycle
- **No state drift** — the running system is always a function of version-controlled Nix config
- **No swap to disk** — zRAM keeps secrets in compressed RAM, never on persistent storage
- **Immutable binaries** — system packages are content-addressed in the Nix store
- **Explicit persistence** — the attack surface is a short, auditable whitelist
- **Default-deny firewall** — only declared ports are open
- **Key-only SSH** — no password authentication

See [docs/architecture.md](docs/architecture.md) for the full security analysis and
attack surface breakdown.

## Documentation

| Document | Contents |
|---|---|
| [Architecture & Security](docs/architecture.md) | 8-layer system design, zRAM rationale, attack surface analysis |
| [Deploying to Hardware](docs/deploying.md) | `dry-activate` → `test` → `switch` workflow with recovery steps |
| [Drive & Storage Config](docs/drive-config.md) | Disk layout, btrfs subvolumes, disko, preservation details |

## Dependencies

| Input | Purpose |
|---|---|
| [nixpkgs](https://github.com/NixOS/nixpkgs) (25.11) | Base packages and NixOS modules |
| [disko](https://github.com/nix-community/disko) | Declarative disk partitioning |
| [preservation](https://github.com/nix-community/preservation) | Bind-mount persistence for tmpfs root |
| [polarbear](https://github.com/kodicw/polarbear) | User configurations (root, charles) |
| [nxbooter](https://github.com/kodicw/nxbooter) | PXE netboot server |
