# Ghost — Hardware Efficiency

> Every byte of RAM costs money. Every wasted disk write shortens SSD
> lifespan. Ghost's design choices squeeze maximum utility from minimum
> hardware, making RAM-based servers practical even when memory prices
> are high.

---

## The Problem

RAM is expensive. At current prices (2024-2025), server DDR5 ECC runs
roughly **$3-5/GB** — meaning a 64GB server costs $200-320 in RAM alone.
When your OS root lives entirely in RAM, every wasted megabyte is money
burned.

Ghost addresses this with a layered compression and efficiency strategy
that reduces RAM pressure, extends SSD lifespan, and keeps the hardware
bill minimal.

---

## zstd — The Compression Choice

Ghost uses **zstd** (Zstandard) in two critical places:

1. **zRAM swap** — compressed swap pages in RAM
2. **btrfs transparent compression** — compressed data on disk

### Why zstd over other algorithms

| Algorithm | Compression ratio | Decompress speed | Compress speed | CPU cost |
|---|---|---|---|---|
| lzo | ~2.0x | Very fast | Fast | Very low |
| lz4 | ~2.1x | Fastest | Fastest | Lowest |
| **zstd** | **~2.8x** | **Fast** | **Fast** | **Low** |
| zlib/gzip | ~3.0x | Moderate | Slow | Moderate |
| xz/lzma | ~3.5x | Slow | Very slow | High |

zstd hits the sweet spot:

- **37% better compression than lz4** (2.8x vs 2.1x) — that's 37% more
  effective RAM from zRAM, and 37% less disk space used
- **Nearly as fast to decompress as lz4** — no perceptible latency
  penalty on reads
- **Low CPU overhead** — modern CPUs handle zstd at near-memory speed;
  the compression is essentially "free" on anything from an Intel N100
  to a Xeon

For a machine with 16GB RAM and 50% zRAM:

| Algorithm | Effective swap | Extra usable memory |
|---|---|---|
| lz4 | ~16.8 GB | +0.8 GB |
| **zstd** | **~22.4 GB** | **+6.4 GB** |
| zlib | ~24.0 GB | +8.0 GB (but slower) |

That's **6.4 GB of extra usable memory** from zstd vs lz4 — at no
dollar cost. With RAM at $4/GB, that's $25 worth of "free" memory.

---

## zRAM — Why Not Disk Swap?

Traditional swap writes memory pages to an SSD or HDD. This has three
problems:

### 1. It's slow

Even a fast NVMe SSD (3500 MB/s sequential) is **10-50x slower** than
RAM (50,000+ MB/s). Random 4K reads — the actual swap access pattern —
are far worse:

| Medium | Random 4K read latency | Throughput |
|---|---|---|
| DDR4 RAM | ~10 ns | ~40,000 MB/s |
| NVMe SSD | ~100 μs | ~500 MB/s (random 4K) |
| SATA SSD | ~200 μs | ~40 MB/s (random 4K) |

zRAM swap is **RAM → compressed RAM**. There's no disk I/O at all. The
"latency" is just the time to decompress, which is microseconds with
zstd.

### 2. It kills SSDs

SSDs have finite write endurance (TBW — terabytes written). Swap is
write-heavy by nature. A busy server can write hundreds of GB/day to
swap, burning through SSD lifespan in months.

zRAM has **zero disk writes** for swap. The SSD only handles `/nix`
(mostly reads) and `/persistent` (small writes for logs and app data).

### 3. It leaks secrets

Swap pages on disk can be recovered forensically. Encryption keys,
session tokens, and passwords that get swapped out become extractable
from the SSD — even after the process exits. zRAM keeps everything in
volatile RAM. Power off = gone.

### The math: zRAM on 16GB

```nix
zramSwap = {
  enable = true;
  algorithm = "zstd";
  memoryPercent = 50;
};
```

- Physical RAM: 16 GB
- zRAM device size: 8 GB (50% of RAM)
- Compression ratio: ~2.8x with zstd
- Effective capacity: ~22.4 GB before OOM
- Cost of equivalent upgrade: $0 (vs ~$25-32 for 8GB DIMM)

---

## btrfs — Why Not ext4 or XFS?

Ghost uses btrfs for the two on-disk subvolumes (`/nix` and
`/persistent`). Here's why:

### Transparent compression

```nix
options = [ "subvol=nix" "compress=zstd" "noatime" ];
```

btrfs compresses data transparently at the filesystem level. This means:

- **The Nix store shrinks dramatically.** A typical NixOS system closure
  is 5-15 GB uncompressed. With zstd, that drops to 2-6 GB on disk.
- **Reads are faster, not slower.** Less data to read from SSD means
  less I/O time. The CPU decompresses faster than the SSD can deliver
  uncompressed data — a net win.
- **Writes are smaller.** Every package install, every `nix build`
  writes less to the SSD. This extends SSD lifespan.

Real-world Nix store compression ratios:

| Content type | Typical ratio | Savings |
|---|---|---|
| ELF binaries | 2.5-3.5x | 60-70% |
| Shared libraries | 2.0-3.0x | 50-67% |
| Python/JS packages | 2.5-4.0x | 60-75% |
| Documentation/text | 3.0-5.0x | 67-80% |
| Already-compressed (images, archives) | 1.0-1.1x | ~0% |

A 10 GB Nix store typically occupies **3-4 GB on disk** with btrfs zstd.

### Subvolumes — free logical partitions

btrfs subvolumes act like flexible partitions without pre-allocating
space:

```
LABEL=nixos (btrfs)
├── subvol: /nix        → mounted at /nix
└── subvol: /persistent → mounted at /persistent
```

Both subvolumes share the same disk space dynamically. If `/nix` needs
80% of the disk and `/persistent` needs 5%, that just works — no
repartitioning needed. With ext4, you'd have to guess partition sizes
upfront and resize later when wrong.

### noatime — eliminating pointless writes

```nix
options = [ ... "noatime" ];
```

By default, Linux updates a file's "last accessed" timestamp on every
read. On a Nix store with thousands of files being read constantly,
this generates enormous write amplification for zero benefit.

`noatime` disables access time updates entirely:

- **Reduces SSD writes by 30-50%** for read-heavy workloads
- **No functional impact** — nothing in NixOS depends on atime
- **Extends SSD lifespan** proportionally

### Copy-on-write (COW) benefits

btrfs is copy-on-write. When data is modified, it writes to a new
location instead of overwriting in place. This provides:

- **Atomic writes** — power loss during a write can't corrupt existing
  data (the old blocks are untouched until the new write completes)
- **Free snapshots** — you can snapshot `/persistent` before a risky
  change and roll back instantly (not currently automated in Ghost, but
  available)
- **No fsck needed** — btrfs is always consistent; no long filesystem
  checks after unclean shutdown

### Why not ext4?

ext4 is reliable but lacks:
- Transparent compression (would need SquashFS or separate tooling)
- Dynamic subvolumes (stuck with fixed partition sizes)
- Copy-on-write atomicity

### Why not XFS?

XFS excels at large-file sequential I/O (video, databases) but:
- No transparent compression
- No subvolumes
- Less suited for the many-small-files pattern of the Nix store

### Why not ZFS?

ZFS has similar capabilities to btrfs (compression, COW, snapshots) but:
- Not in mainline Linux kernel (DKMS module or nixpkgs rebuild)
- Heavier RAM overhead (ARC cache, per-block checksums)
- More complex administration for a single-disk setup
- GPL license conflict with Linux kernel

For a single-disk server like Ghost, btrfs gives 90% of ZFS's benefits
with none of the operational complexity.

---

## systemd-boot — Smallest Possible Bootloader

Ghost uses systemd-boot instead of GRUB:

| | GRUB | systemd-boot |
|---|---|---|
| Size | ~2-5 MB installed | ~120 KB EFI binary |
| Features | Filesystem drivers, network boot, scripting, themes | Boot menu, nothing else |
| Config | Generated `grub.cfg` (can fail) | Simple `.conf` files |
| Attack surface | Large (CVEs in filesystem parsing, font rendering) | Minimal |
| ESP size needed | ~200 MB minimum | ~50 MB practical |

For Ghost, the bootloader's only job is to load the kernel and initrd.
systemd-boot does exactly that with the smallest possible code footprint
on the ESP.

### ESP umask=0077

```nix
mountOptions = [ "umask=0077" ];
```

The ESP (EFI System Partition) contains the bootloader and kernel. By
restricting it to root-only access, unprivileged users can't read kernel
images (which could reveal security features) or modify boot binaries.

---

## tmpfs Root Sizing — The 3GB Decision

```nix
fileSystems."/" = {
  device = "none";
  fsType = "tmpfs";
  options = [ "defaults" "size=3G" "mode=755" ];
};
```

Why 3 GB and not more or less?

### What lives in tmpfs root

| Path | Typical size | Notes |
|---|---|---|
| `/etc` | 5-20 MB | Generated from Nix store on boot |
| `/run` | 50-200 MB | Runtime state, systemd, tmpfiles |
| `/var` (non-persistent) | 10-50 MB | Ephemeral portions |
| Docker overlay (ephemeral) | 0-2 GB | Container layer cache |
| Package builds (if any) | 0-1 GB | Temporary during `nix build` |

**Typical idle usage:** 200-400 MB
**Peak with Docker activity:** 1-2 GB
**Headroom for spikes:** ~1 GB

3 GB provides comfortable margin without over-allocating RAM that could
be used for actual workloads or zRAM swap.

### Why not more?

tmpfs `size=` sets the **maximum**, not the allocation. tmpfs only
consumes RAM for data actually stored in it. A 3G tmpfs with 300 MB of
data uses 300 MB of RAM.

However, if something fills the tmpfs to 3 GB (e.g., a runaway log or
Docker build), that's 3 GB of RAM unavailable for applications. A lower
limit acts as a safety valve — the system returns "disk full" errors
rather than silently consuming all RAM and triggering OOM kills.

### Why not less?

Below 2 GB, Docker overlay layers and NixOS activation scripts can run
into space issues during deployments. 3 GB gives enough room for a
`nixos-rebuild switch` to stage the new system without running out of
tmpfs space.

---

## Minimum Hardware Requirements

Given all these efficiency choices, Ghost runs comfortably on surprisingly
modest hardware:

| Component | Minimum | Recommended | Notes |
|---|---|---|---|
| CPU | 2 cores, x86_64 | 4+ cores | Any modern Intel/AMD; N100 works great |
| RAM | 4 GB | 8-16 GB | 3G tmpfs + zRAM makes 8 GB act like 12-14 |
| Storage | 32 GB SSD | 64-128 GB SSD | btrfs zstd compresses Nix store ~3x |
| Network | 1 Gbps | 1 Gbps | Needed for Docker image pulls |
| Boot | UEFI | UEFI | Legacy BIOS not supported (systemd-boot) |

### Example: Intel N100 Mini PC ($120-150)

- 4 cores / 4 threads, 3.4 GHz burst
- 8 GB DDR5 (soldered)
- 128 GB NVMe
- 2x 2.5 GbE

With Ghost's efficiency stack:
- **Effective memory:** ~14 GB (8 GB physical + zRAM zstd)
- **Usable disk after Nix store:** ~100 GB (btrfs zstd)
- **SSD lifespan:** 5+ years (noatime + no swap writes + compression)
- **Power draw:** 6-10W idle

This $130 box runs Docker containers, Grist, Tailscale, and Prometheus
monitoring — with the security properties of an ephemeral OS and
enterprise-grade persistence.

---

## Summary: Cost of Each Efficiency Choice

| Choice | RAM saved | Disk saved | SSD wear saved | Security benefit | Cost |
|---|---|---|---|---|---|
| zRAM (zstd, 50%) | +40% effective | — | 100% (no swap writes) | Secrets stay in RAM | $0 |
| btrfs zstd | — | ~60-70% | ~60-70% fewer writes | — | $0 |
| btrfs noatime | — | — | ~30-50% fewer writes | — | $0 |
| tmpfs root (3G) | -3G max | — | 100% (no root writes) | Ephemeral by default | $0 |
| systemd-boot | — | ~4 MB | — | Smaller attack surface | $0 |

**Total additional cost: $0.**

Every efficiency choice is a software configuration. No special hardware
required. No paid licenses. No proprietary tools. Just informed defaults
that make cheap hardware punch above its weight.
