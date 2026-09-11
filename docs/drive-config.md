# Ghost — Drive & Storage Configuration

> Research findings on how disks, filesystems, and storage are configured across the Ghost deployment.

---

## Table of Contents

- [Overview](#overview)
- [Architecture: RAM Root + Btrfs Persistence](#architecture-ram-root--btrfs-persistence)
- [Disko: Declarative Disk Partitioning](#disko-declarative-disk-partitioning)
- [Filesystem Layout](#filesystem-layout)
- [The `hardware.nix` Mounts](#the-hardware-nix-mounts)
- [Persistence via `preservation`](#persistence-via-preservation)
- [zRAM Swap](#zram-swap)
- [Ghost-fs: Dedicated Storage Host](#ghost-fs-dedicated-storage-host)
- [Deployment Paths](#deployment-paths)
- [Key Design Decisions](#key-design-decisions)

---

## Overview

Ghost has **two host profiles** with different drive strategies:

| Profile | Role | Drive Config |
|---|---|---|
| `ghost` | Docker host (general purpose) | 1 disk → btrfs subvolumes + tmpfs root |
| `ghost-fs` | Dedicated storage host | 1 system disk + 3 data disks (ext4) + SeaweedFS |

Both share the same base (`disko.nix` + `hardware.nix`) and overlay host-specific mounts on top.

---

## Architecture: RAM Root + Btrfs Persistence

The core idea: **the OS lives in RAM; only persistent state touches disk.**

```
┌─────────────────────────────────────────────┐
│                 tmpfs (RAM)                  │
│  /           size=3G  mode=755              │
│  /tmp       tmpfs, cleaned on boot          │
│  /run       tmpfs                           │
├─────────────────────────────────────────────┤
│              Btrfs disk (SSD/NVMe)          │
│  /nix          subvol=nix     compress=zstd │
│  /persistent   subvol=persistent comp=zstd  │
│  /boot         vfat (ESP 512M)              │
└─────────────────────────────────────────────┘
```

Key properties:
- **`/` is tmpfs** — every boot starts clean (set in `hardware.nix`)
- **`/nix`** — stores Nix store and system closures (btrfs subvol, compressed)
- **`/persistent`** — stores everything that must survive reboot (btrfs subvol, compressed)
- **`/boot`** — EFI System Partition (vfat)

---

## Disko: Declarative Disk Partitioning

File: [`disko.nix`](./disko.nix)

Uses [nix-community/disko](https://github.com/nix-community/disko) to **declaratively define the disk layout**. The config is applied on initial install via `nixos-anywhere` or manually with `disko`.

### Partition table

```
┌─────── GPT ──────────────────────────────────┐
│ ESP (vfat)    512M   /boot  umask=0077       │
├──────────────────────────────────────────────┤
│ Btrfs         100%    LABEL=nixos            │
│   ├── subvol: /nix        → /nix             │
│   └── subvol: /persistent → /persistent      │
└──────────────────────────────────────────────┘
```

### Device reference

The disk device is **not hardcoded** — it uses `lib.mkDefault "/dev/sda"` so it can be overridden:

- **`disko.nix`**: `device = lib.mkDefault "/dev/sda"`
- **`justfile`**: `disk_device := env_var_or_default("DISK_DEVICE", "/dev/sda")`
- **`nixos-anywhere`**: pass `--disk-device /dev/nvme0n1` to override

This means the same config works for SATA SSDs (`/dev/sda`), NVMe drives (`/dev/nvme0n1`), or virtual disks.

### Subvolume structure

```bash
$ btrfs subvolume list /mnt
ID 256 gen 5 top level 5 path nix
ID 257 gen 6 top level 5 path persistent
```

Both subvolumes use `compress=zstd` and `noatime` for performance.

---

## The `hardware.nix` Mounts

File: [`hardware.nix`](./hardware.nix)

Maps the disko layout into the running system:

| Mountpoint | Device | FsType | Options | NeededForBoot |
|---|---|---|---|---|
| `/` | `none` | tmpfs | size=3G, mode=755 | — |
| `/nix` | `LABEL=nixos` | btrfs | subvol=nix, compress=zstd, noatime | ✅ |
| `/persistent` | `LABEL=nixos` | btrfs | subvol=persistent, compress=zstd, noatime | ✅ |

Uses `lib.mkForce` to ensure these take precedence over the `mkDefault` in disko.

Also defines:
- **Bootloader**: `systemd-boot` (EFI)
- **Kernel modules**: `xhci_pci`, `ahci`, `nvme`, `usbhid`, `usb_storage`, `sd_mod`, `e1000e`, `r8169`, `igb`
- **CPU**: KVM Intel (`kvm-intel`)
- **Firmware**: redistributable firmware enabled
- **Network**: DHCP (default)

---

## Persistence via `preservation`

File: [`modules/nixos/persistence.nix`](./modules/nixos/persistence.nix)

Uses [nix-community/preservation](https://github.com/nix-community/preservation) to declare which files and directories survive reboots.

All preserved paths live under the `/persistent` btrfs subvol:

```nix
preservation.preserveAt."/persistent" = {
  directories = [
    "/var/lib/docker"         # Docker volumes & container metadata
    "/var/lib/portainer"      # Portainer state (legacy)
    "/var/lib/tailscale"      # Tailscale keys & state
    "/var/lib/nixos"          # NixOS generated config
    "/var/lib/systemd"        # Systemd journal (persistent logging)
    "/var/lib/grist"          # Grist application data
    "/var/log"                # System logs
    "/etc/NetworkManager/system-connections"  # Network profiles
    "/opt"                    # Misc installed software
    { directory = "/etc/ssh"; inInitrd = true; }  # SSH host keys (in initrd)
  ];
  files = [
    { file = "/etc/machine-id"; inInitrd = true; }
  ];
};
```

### What gets wiped on reboot (intentionally not persisted)

- `/root/.bash_history` — no shell history
- `/home/charles` — user home is ephemeral
- `/tmp` — cleaned on boot via `boot.tmp.cleanOnBoot = true`
- `/var/tmp` — transient
- `/run` — tmpfs, cleaned on boot

### Why `inInitrd` for SSH keys and machine-id

`inInitrd = true` means these files are mounted **before the root filesystem** during early boot. This is critical because:
- **SSH host keys** need to be available before `sshd` starts
- **`machine-id`** must exist before `systemd` journal and other services initialize

Without this, every boot would generate new SSH host keys (triggering "host key changed" warnings) and a new machine-id.

---

## zRAM Swap

File: [`modules/nixos/core.nix`](./modules/nixos/core.nix)

```nix
zramSwap = {
  enable = true;
  algorithm = "zstd";
  memoryPercent = 50;
};
```

- Creates a compressed block device in RAM for swap
- Uses **zstd** compression (fast, good ratio)
- Allocates up to **50% of RAM** for compressed swap
- Critical for a tmpfs-root system — `/nix` is on disk but build operations and formula execution (Grist Python sandbox) can still benefit from additional memory headroom

---

## Ghost-fs: Dedicated Storage Host

File: [`hosts/ghost-fs.nix`](./hosts/ghost-fs.nix)

A separate NixOS configuration (`ghost-fs`) for a machine with **3 additional data disks** running SeaweedFS.

### Disk layout

| Device | Mount | FsType | Purpose |
|---|---|---|---|
| `/dev/sda` (via disko) | `/`, `/nix`, `/persistent` | btrfs + tmpfs | System (same as ghost) |
| `/dev/sdb` | `/mnt/disk1` | ext4 | SeaweedFS volume 1 |
| `/dev/sdc` | `/mnt/disk2` | ext4 | SeaweedFS volume 2 |
| `/dev/sdd` | `/mnt/disk3` | ext4 | SeaweedFS volume 3 |

> **Note**: The config uses `/dev/sdX` directly as a placeholder. The comment says to replace with UUIDs for production reliability.

### SeaweedFS

[SeaweedFS](https://github.com/seaweedfs/seaweedfs) is a distributed file store. On ghost-fs:

- **Master** (metadata server): binds to `127.0.0.1:9333`
- **Volume** (data server): stores data across the 3 ext4 disks, up to 100 volumes per disk
- Firewall opens port 9333 (master) and 8080 (volume)

The service is defined as a NixOS module in [`modules/nixos/seaweedfs.nix`](./modules/nixos/seaweedfs.nix) with systemd unit hardening (ProtectSystem, NoNewPrivileges, PrivateTmp, etc.).

---

## Deployment Paths

### Fresh install (anywhere)

```bash
# Override disk device if not /dev/sda
just anywhere device=/dev/nvme0n1 target=root@<ip>
```

This runs `nixos-anywhere` with the disko config, which:
1. Partitions the disk (GPT + ESP + Btrfs)
2. Creates subvolumes
3. Mounts everything
4. Installs NixOS closure

### Netboot (PXE deploy)

```bash
just netboot
```

Uses `nxbooter` to PXE boot the `ghost-netboot` config. This variant includes `netboot-minimal.nix` and runs entirely in RAM — no disk needed.

### ISO install

```bash
just build-iso
just flash-usb device=/dev/sdX
```

The `ghost-iso` config generates a bootable ISO. Note: it forces `preservation.enable = false` and overrides `/` device to `nixos-iso` since this is a live environment.

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| **tmpfs root** | Eliminates disk writes for OS files; faster boot; forces service separation |
| **Btrfs subvolumes** | `compress=zstd` saves space; subvols allow independent snapshot/rollback of `/nix` vs `/persistent` |
| **`/nix` on disk** | Nix store is large (closures, generations); too big for tmpfs with 3G limit |
| **`/persistent` on disk** | Docker volumes, Tailscale keys, SSH host keys must survive reboot |
| **Declarative disko** | Single source of truth for partition layout; reproducible installs |
| **Preservation module** | Explicit whitelist of what persists — nothing leaks accidentally |
| **zRAM swap** | Compressed RAM swap extends headroom without disk I/O |
| **Label-based mounting** | `LABEL=nixos` is stable across device renames; faster than UUID in some scenarios |
| **Separate storage host** | SeaweedFS on `ghost-fs` keeps data plane off the main Docker host |
| **Ghost-fs uses ext4 for data** | Simpler, proven for bulk storage; SeaweedFS handles replication/erasure coding at app layer |
