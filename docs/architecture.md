# Ghost — Architecture & Security

> Why Ghost runs the way it does: tmpfs root, preservation whitelist,
> zRAM swap, content-addressed Nix store, and the security properties
> that emerge from combining them.

---

## Table of Contents

- [Design Philosophy](#design-philosophy)
- [System Architecture](#system-architecture)
- [Layer 1: tmpfs Root — Ephemeral by Default](#layer-1-tmpfs-root--ephemeral-by-default)
- [Layer 2: The Nix Store — Immutable and Content-Addressed](#layer-2-the-nix-store--immutable-and-content-addressed)
- [Layer 3: Preservation — Explicit Persistence Whitelist](#layer-3-preservation--explicit-persistence-whitelist)
- [Layer 4: zRAM — Compressed Swap Without Disk Leakage](#layer-4-zram--compressed-swap-without-disk-leakage)
- [Layer 5: Firewall, SSH & Network](#layer-5-firewall-ssh--network)
- [Layer 6: Containers — Isolated Workloads](#layer-6-containers--isolated-workloads)
- [Layer 7: Boot Chain — systemd-boot + systemd initrd](#layer-7-boot-chain--systemd-boot--systemd-initrd)
- [Layer 8: Monitoring & Observability](#layer-8-monitoring--observability)
- [What the Full Config Looks Like](#what-the-full-config-looks-like)
- [Attack Surface Analysis](#attack-surface-analysis)
- [What This Does NOT Protect Against](#what-this-does-not-protect-against)

---

## Design Philosophy

Traditional servers accumulate state over time — config edits, dropped
binaries, stale cron jobs, forgotten user accounts. This **state drift**
is invisible, undocumented, and expands the attack surface with every
passing day.

Ghost inverts this model:

> **Nothing persists unless explicitly declared.
> Everything else is rebuilt from source on every boot.**

This is achieved by combining four properties:

1. The root filesystem is **RAM** (tmpfs) — wiped on every reboot
2. System binaries live in the **Nix store** — immutable and hash-verified
3. Persistent state is an **explicit whitelist** — auditable in a single file
4. Swap is **compressed RAM** (zRAM) — no sensitive data touches disk

---

## System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     RAM (tmpfs)                               │
│                                                               │
│  /              Rebuilt from Nix store on every boot          │
│  /etc           Generated from NixOS config, ephemeral       │
│  /root          Ephemeral home directory                     │
│  /tmp           tmpfs, cleaned on boot                       │
│  /run           Ephemeral runtime state                      │
│  zRAM swap      Compressed swap in RAM (zstd, 50% of RAM)   │
│                                                               │
├──────────────────────────────────────────────────────────────┤
│                     Btrfs SSD (LABEL=nixos)                   │
│                                                               │
│  /nix           Nix store — immutable, content-addressed     │
│                 subvol=nix, compress=zstd, noatime           │
│                                                               │
│  /persistent    Preservation whitelist — bind-mounted back   │
│                 subvol=persistent, compress=zstd, noatime    │
│                                                               │
├──────────────────────────────────────────────────────────────┤
│                     EFI System Partition (vfat, 512M)         │
│                                                               │
│  /boot          systemd-boot, kernel, initrd                 │
│                 umask=0077 (owner-only access)                │
└──────────────────────────────────────────────────────────────┘
```

---

## Layer 1: tmpfs Root — Ephemeral by Default

**File:** [`hardware.nix`](./hardware.nix)

```nix
fileSystems."/" = lib.mkForce {
  device = "none";
  fsType = "tmpfs";
  options = [ "defaults" "size=3G" "mode=755" ];
};
```

Additionally, `/tmp` is explicitly RAM-backed and cleaned on boot
([`core.nix`](./modules/nixos/core.nix)):

```nix
boot.tmp.useTmpfs = true;
boot.tmp.cleanOnBoot = true;
```

The root filesystem is a 3GB tmpfs — it lives entirely in RAM. On every
boot, the system starts from a clean slate. The Nix store populates
`/etc`, `/usr`, `/bin`, and all system paths from the immutable store.

### What this means for security

Every reboot is a full system reset. There is no way for an attacker to
persistently modify system files through the filesystem alone:

| Path | Traditional Linux | Ghost |
|---|---|---|
| `/etc/passwd`, `/etc/shadow` | Mutable, attacker adds user | Regenerated from Nix config on boot |
| `/etc/pam.d/*` | Attacker weakens auth | Rebuilt from Nix store |
| `/etc/cron.d/*` | Persistent backdoor crons | Wiped on reboot |
| `/usr/local/bin` | Dropped malware | Gone on reboot |
| `/root/.ssh/authorized_keys` | Attacker adds their key | Wiped — keys come from Nix config |
| `/etc/systemd/system/*` | Rogue services | Rebuilt from Nix store |
| `/var/spool/cron` | Persistent cron backdoor | Wiped on reboot |

### Why 3GB?

The running NixOS system (excluding `/nix` and `/persistent`, which are
on disk) needs roughly 200-500MB for `/etc`, `/run`, runtime state, and
service working directories. 3GB provides comfortable headroom for
Docker overlay layers, temporary files, and build operations without
risking an OOM situation.

---

## Layer 2: The Nix Store — Immutable and Content-Addressed

**Mount:** `/nix` → btrfs subvolume `nix`, `compress=zstd`, `noatime`

The Nix store (`/nix/store`) contains every package, configuration file,
and system closure. Each path is named by its cryptographic hash:

```
/nix/store/3hgg7pr65imdrifqqh3flg3arvkc2r22-bash-5.3p3/
/nix/store/8cmw5l53nyywznbd0xpiy7wacra60bv8-nixos-system-ghost-25.11/
```

### Security properties

- **Immutable by convention** — NixOS treats store paths as read-only.
  Modifying a store path breaks its hash, which breaks every derivation
  that references it.
- **Content-addressed** — two identical builds produce the same hash.
  Tampering is detectable.
- **No in-place updates** — upgrading a package creates a new store path;
  the old one remains until garbage-collected. This means rollbacks are
  instant and safe.

---

## Layer 3: Preservation — Explicit Persistence Whitelist

**File:** [`modules/nixos/persistence.nix`](./modules/nixos/persistence.nix)
**Module:** [nix-community/preservation](https://github.com/nix-community/preservation)

This is the security linchpin. Only paths explicitly listed here survive
a reboot. Everything else is gone.

```nix
preservation.preserveAt."/persistent" = {
  directories = [
    "/var/lib/docker"                        # Container volumes & metadata
    "/var/lib/portainer"                     # Portainer state
    "/var/lib/tailscale"                     # Tailscale identity & keys
    "/var/lib/nixos"                         # NixOS generated UIDs/GIDs
    "/var/lib/systemd"                       # Journal, timers, state
    "/var/log"                               # System logs
    "/etc/NetworkManager/system-connections" # Saved network profiles
    "/opt"                                   # Optional installed software
    { directory = "/etc/ssh"; inInitrd = true; }  # SSH host keys
  ];
  files = [
    { file = "/etc/machine-id"; inInitrd = true; }
  ];
};
```

The Grist module ([`grist.nix`](./modules/nixos/grist.nix)) adds one
more preserved path:

```nix
preservation.preserveAt."/persistent".directories = [ "/var/lib/grist" ];
```

### How it works

The `preservation` module creates systemd bind mounts from
`/persistent/<path>` → `/<path>`. The backing data lives on the btrfs
subvolume; the bind mount makes it appear at the expected location.

For paths marked `inInitrd = true`, the mount happens in the initramfs
**before systemd starts**. This is critical for:

- **`/etc/ssh`** — SSH host keys must exist before `sshd` starts, or
  every reboot generates new keys (triggering "host key changed" warnings)
- **`/etc/machine-id`** — systemd and the journal require a stable
  machine ID from the first moment of boot

### machine-id commit prevention

Because preservation handles `/etc/machine-id`, Ghost disables systemd's
built-in machine-id commit service to avoid conflicts
([`core.nix`](./modules/nixos/core.nix)):

```nix
systemd.services.systemd-machine-id-commit.enable = false;
systemd.services.systemd-machine-id-commit.unitConfig.ConditionPathExists = "!/etc/machine-id";
```

### What is NOT on the whitelist (and why)

| Path | Why it's ephemeral |
|---|---|
| `/etc/passwd`, `/etc/shadow` | Rebuilt from Nix config — users are declarative |
| `/etc/pam.d/*` | Derived from NixOS modules — never hand-edited |
| `/home/*` | User homes are ephemeral; dotfiles come from home-manager if needed |
| `/root/*` | No persistent root home; prevents forensic artifacts |
| `/var/tmp` | Temporary data — no reason to persist |
| `/etc/resolv.conf` | Generated by DHCP/NetworkManager on every boot |
| `/usr`, `/bin`, `/lib` | Symlinks into the Nix store — rebuilt on activation |

### The audit question

To audit Ghost's persistent attack surface, you only need to answer:
**"What's in `/persistent`?"** — that's the entire scope.

---

## Layer 4: zRAM — Compressed Swap Without Disk Leakage

**File:** [`modules/nixos/core.nix`](./modules/nixos/core.nix)

```nix
zramSwap = {
  enable = true;
  algorithm = "zstd";
  memoryPercent = 50;
};
```

Combined with no on-disk swap devices in
[`hardware.nix`](./hardware.nix) — there are **zero** swap partitions
defined on disk.

### Why this matters for security

Traditional swap writes memory pages to disk. This means:

- Encryption keys in memory can end up on disk
- Passwords, tokens, and session data can be recovered from swap
- Forensic tools can extract sensitive data from swap partitions

Ghost uses **zero on-disk swap**. Instead, zRAM creates a compressed
block device in RAM:

```
RAM (physical)
├── Active memory (working set)
├── zRAM swap (compressed, up to 50% of RAM, zstd)
│   └── Pages that would normally go to disk swap
│       are compressed and kept in RAM
└── tmpfs root (shares remaining RAM)
```

With zstd compression, zRAM typically achieves 2-3x compression ratio,
effectively giving 50% of RAM × 2-3x = 100-150% of RAM as usable
memory before OOM.

**The result:** Sensitive data in memory stays in memory. It never
touches persistent storage. Power off = data gone.

---

## Layer 5: Firewall, SSH & Network

**File:** [`modules/nixos/networking.nix`](./modules/nixos/networking.nix)

### Firewall

```nix
networking.firewall.allowedTCPPorts = [ 22 9000 9323 ];
networking.firewall.trustedInterfaces = [ "tailscale0" ];
```

The Grist module adds port `8484`:

```nix
networking.firewall.allowedTCPPorts = [ 8484 ];
```

| Port | Service | Purpose |
|---|---|---|
| 22 | SSH | Remote administration (key-only) |
| 8484 | Grist | Spreadsheet application |
| 9000 | Node Exporter | Prometheus system metrics |
| 9323 | Docker metrics | Prometheus Docker daemon metrics |

The Tailscale interface (`tailscale0`) is **fully trusted** — all
traffic from the Tailscale mesh bypasses the firewall. All other ports
are **dropped by default** (iptables DROP policy).

### SSH

```nix
services.openssh.enable = true;
services.getty.autologinUser = lib.mkForce "root";
```

- SSH is enabled with default NixOS hardening
- The authorized key is declared in the `polarbear` Nix module (not a
  mutable `authorized_keys` file)
- Console auto-login as root for local/IPMI access
- Because `/root/.ssh` is on tmpfs, an attacker who adds a key to
  `authorized_keys` at runtime loses it on reboot

### Tailscale — Zero-Trust Overlay

```nix
services.tailscale.enable = true;
```

Tailscale provides a WireGuard-based overlay network. Services can be
exposed only to the tailnet instead of the public internet. The Tailscale
identity and keys are persisted in `/var/lib/tailscale` (on the
preservation whitelist).

### Avahi — Local Service Discovery

```nix
services.avahi = {
  enable = true;
  nssmdns4 = true;
  openFirewall = true;
  publish = {
    enable = true;
    addresses = true;
    domain = true;
    hinfo = true;
    userServices = true;
    workstation = true;
  };
};
```

Enables `ghost.local` mDNS resolution on the LAN. Publishes addresses,
domain, hardware info, and user services for zero-config discovery.

---

## Layer 6: Containers — Isolated Workloads

**Files:** [`modules/nixos/docker.nix`](./modules/nixos/docker.nix),
[`modules/nixos/grist.nix`](./modules/nixos/grist.nix)

### Docker

```nix
virtualisation.docker = {
  enable = true;
  autoPrune.enable = true;
  daemon.settings = {
    metrics-addr = "0.0.0.0:9323";
    experimental = true;
  };
};

users.users.charles.extraGroups = [ "docker" ];
users.users.root.extraGroups = [ "docker" ];
```

- Weekly auto-prune removes unused images and containers
- Docker daemon exposes Prometheus metrics on port 9323
- Users `root` and `charles` are in the `docker` group
- Docker data (`/var/lib/docker`) is on the preservation whitelist

### Grist (OCI Container)

```nix
virtualisation.oci-containers.containers.grist = {
  image = "gristlabs/grist";
  ports = [ "8484:8484" ];
  volumes = [ "/var/lib/grist:/persist" ];
  environment = {
    APP_HOME_URL = "http://ghost.local:8484";
    GRIST_SINGLE_ORG = "docs";
  };
  environmentFiles = [ "/var/lib/grist/env" ];  # Secrets at runtime
};
```

**Security notes:**

- Secrets (`GRIST_SESSION_SECRET`) are loaded from `/var/lib/grist/env`
  on the host — **never** in the Nix config or git
- The container's persistent data is isolated to `/var/lib/grist`

---

## Layer 7: Boot Chain — systemd-boot + systemd initrd

**File:** [`hardware.nix`](./hardware.nix)

```nix
boot.loader.systemd-boot.enable = lib.mkDefault true;
boot.loader.systemd-boot.graceful = true;
boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
boot.initrd.systemd.enable = true;
```

### Why systemd-boot (not GRUB)

- **Smaller attack surface** — systemd-boot is a minimal EFI stub; GRUB
  is a full-featured bootloader with its own filesystem drivers, scripting
  language, and network stack
- **No configuration file parsing** — boot entries are simple `.conf`
  files in the ESP
- **Graceful fallback** — `graceful = true` prevents boot failures from
  bricking the system if the ESP is momentarily inaccessible

### Why systemd initrd

- **Proper unit ordering** for early mounts — critical for `inInitrd`
  preservation mounts (`/etc/ssh`, `/etc/machine-id`)
- **Journal logging from initrd** — boot failures are captured in the
  journal
- **Consistent service management** — same systemd tooling from initrd
  through shutdown

### ESP Security

```nix
# In disko.nix
content.format = "vfat";
mountOptions = [ "umask=0077" ];  # Owner-only access
```

The EFI System Partition is mounted with `umask=0077`, restricting access
to root only.

### Hardware Support

```nix
boot.initrd.availableKernelModules = [
  "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod"
  "e1000e" "r8169" "igb"  # NIC drivers in initrd
];
boot.initrd.supportedFilesystems = [ "btrfs" ];
boot.initrd.kernelModules = [ "btrfs" ];
boot.kernelModules = [ "kvm-intel" "ipmi_si" "ipmi_devintf" "ipmi_msghandler" ];
hardware.enableRedistributableFirmware = true;
```

- NIC drivers loaded in initrd for potential remote unlock / early networking
- **IPMI modules** loaded for out-of-band hardware management (`ipmitool`
  is installed in system packages)
- **KVM** enabled for running VMs if needed
- Redistributable firmware for hardware compatibility

---

## Layer 8: Monitoring & Observability

**File:** [`modules/nixos/monitoring.nix`](./modules/nixos/monitoring.nix)

```nix
services.prometheus.exporters.node = {
  enable = true;
  port = 9000;
  enabledCollectors = [ "systemd" "tcpstat" ];
};
```

Two metrics endpoints are exposed:

| Endpoint | Port | Source | Metrics |
|---|---|---|---|
| Node Exporter | 9000 | `monitoring.nix` | CPU, memory, disk, network, systemd unit states, TCP stats |
| Docker daemon | 9323 | `docker.nix` | Container count, runtime, image stats |

These enable external monitoring to detect service failures, unusual
resource usage, disk space exhaustion on `/persistent`, and network
anomalies.

---

## What the Full Config Looks Like

Every component is a NixOS module imported in [`flake.nix`](./flake.nix):

```
flake.nix
├── disko.nix                    Declarative disk partitioning
├── hardware.nix                 tmpfs root, btrfs mounts, boot chain
└── modules/nixos/
    ├── core.nix                 zRAM, SSH, IPMI, base packages, stateVersion
    ├── persistence.nix          Preservation whitelist
    ├── networking.nix           Firewall, Tailscale, Avahi
    ├── docker.nix               Docker daemon, metrics, auto-prune
    ├── grist.nix                Grist OCI container, secrets, persistence
    └── monitoring.nix           Prometheus Node Exporter
```

External modules:
- **disko** — translates `disko.nix` into partition commands
- **preservation** — implements bind-mount persistence from `/persistent`
- **polarbear** — provides user configurations (root, charles)
- **nxbooter** — PXE netboot support

### System packages

From [`core.nix`](./modules/nixos/core.nix):

```
curl  git  htop  zellij  neovim  wget  ipmitool
```

Minimal set: network tools, editor, terminal multiplexer, monitoring,
and hardware management. No compilers, no development tools, no
unnecessary attack surface.

---

## Attack Surface Analysis

### What an attacker with root access CAN do

| Action | Persists across reboot? |
|---|---|
| Modify `/etc/passwd` | ❌ No — rebuilt from Nix config |
| Drop binary in `/usr/bin` | ❌ No — tmpfs, wiped |
| Add SSH authorized key to `/root/.ssh` | ❌ No — tmpfs, wiped |
| Install kernel module | ❌ No — tmpfs, wiped |
| Create systemd service | ❌ No — tmpfs, wiped |
| Add cron job | ❌ No — tmpfs, wiped |
| Modify Docker container/volume | ⚠️ **Yes** — `/var/lib/docker` is persisted |
| Modify Grist data | ⚠️ **Yes** — `/var/lib/grist` is persisted |
| Tamper with system logs | ⚠️ **Yes** — `/var/log` is persisted |
| Modify SSH host keys | ⚠️ **Yes** — `/etc/ssh` is persisted |
| Modify Tailscale identity | ⚠️ **Yes** — `/var/lib/tailscale` is persisted |
| Read secrets from `/var/lib/grist/env` | ⚠️ **Yes** — file is on disk |
| Run in-memory malware (no disk) | ✅ Yes (until reboot) |

### The persistent attack surface (exhaustive)

This is the **complete** list of what survives a reboot:

```
/persistent/
├── etc/
│   ├── machine-id                          # 32-byte machine identifier
│   ├── ssh/                                # SSH host keys
│   └── NetworkManager/system-connections/  # Network profiles
├── var/
│   ├── lib/
│   │   ├── docker/        # Container images, volumes, overlay layers
│   │   ├── grist/         # Grist data + env secrets file
│   │   ├── portainer/     # Portainer state
│   │   ├── tailscale/     # Tailscale identity & WireGuard keys
│   │   ├── nixos/         # NixOS UID/GID mappings
│   │   └── systemd/       # Journal, timer state
│   └── log/               # System logs (journal, service logs)
└── opt/                   # Optional software
```

That's it. That is the entire persistent filesystem. Everything else is
either RAM (tmpfs) or the immutable Nix store.

---

## What This Does NOT Protect Against

| Threat | Why tmpfs doesn't help |
|---|---|
| **Runtime memory exploits** | Kernel exploits, in-memory malware live until reboot |
| **Compromised persistent data** | Attacker modifies Docker volumes or Grist data — these persist |
| **Supply chain attacks** | Malicious package in flake inputs ends up in the Nix store |
| **Secrets on disk** | `/var/lib/grist/env` contains secrets and is on btrfs |
| **Network attacks** | tmpfs doesn't affect network-layer security |
| **Physical access** | Attacker with physical access can boot from USB, read btrfs |
| **Compromised Tailscale identity** | Tailscale keys are persisted; stolen identity persists |

### Mitigations for these gaps

- **Runtime exploits** → reboot clears them; monitoring detects anomalies
- **Persistent data tampering** → Docker content trust, Grist backups
- **Supply chain** → pin flake inputs, review updates, use `flake.lock`
- **Secrets** → consider LUKS encryption for the btrfs volume
- **Physical access** → Secure Boot (not currently enabled), BIOS password
- **Network** → Tailscale (zero-trust), firewall (default-deny), SSH key-only
