# Ghost — Deploying to Hardware

> How to safely deploy configuration changes to a running Ghost instance using `nixos-rebuild`.

---

## ⚠️ Read This First

Ghost runs on **tmpfs root** — the OS lives in RAM. This means a bad deploy won't brick the disk, but it *can* make the machine unreachable until you physically reboot it. The three-stage deploy process below exists to catch problems **before** they take effect.

**Never skip straight to `switch`.** Always go through the stages in order.

---

## The Three Stages

```
 dry-activate          test              switch
 ────────────►    ────────────►    ────────────►
  "what would      "try it, but      "make it
   change?"         I can undo"       permanent"

  Zero risk.       Low risk.         Committed.
  Nothing runs.    Rolls back         This is the
  Just a diff.     automatically      new system.
                   if you lose
                   connection.
```

Each stage gives you a checkpoint to stop if something looks wrong.

---

## Prerequisites

Before deploying, make sure:

1. **The configuration evaluates** — build it locally first:
   ```bash
   just test
   ```

2. **The VM test passes** — proves persistence + tmpfs survives reboot:
   ```bash
   just check-vm
   ```

3. **You have SSH access** to the target machine (default: `root@<ip>`).

4. **You know the target's current state** — SSH in and check:
   ```bash
   ssh root@<ip> "systemctl is-system-running && uname -r"
   ```

---

## Stage 1: `dry-activate`

**What it does:** Builds the new system closure, copies it to the target, then shows you exactly what would change — *without changing anything*.

```bash
nixos-rebuild dry-activate \
  --flake .#ghost \
  --target-host root@<ip>
```

**What to look for:**

- **Services that would restart** — is anything unexpected restarting?
- **New packages** being pulled in
- **Removed packages** — did you accidentally drop something?
- **Configuration file changes** — `/etc` diffs

**Example output:**
```
would restart the following units: docker.service, prometheus-node-exporter.service
would stop the following units: docker-grist.service
would start the following units: docker-grist.service
```

> **Why this matters:** This is your free look. If you see a service you don't expect restarting (like `sshd` or `networking`), investigate *before* moving on. Restarting `sshd` on a remote machine could lock you out if the config is wrong.

**Decision point:**
- Output looks expected → proceed to Stage 2
- Something unexpected → stop, investigate, fix config, rebuild

---

## Stage 2: `test`

**What it does:** Activates the new configuration **immediately**, but does **not** add it to the bootloader. If the machine reboots (or you reboot it), it goes back to the previous working configuration.

```bash
nixos-rebuild test \
  --flake .#ghost \
  --target-host root@<ip>
```

**What happens on the target:**

1. The new system closure is activated
2. Services are started/stopped/restarted as needed
3. The bootloader is **not** touched — old config is still the boot default
4. If you lose SSH, the machine can be recovered by rebooting

**What to verify after `test`:**

```bash
# SSH in and check
ssh root@<ip>

# Is the system healthy?
systemctl is-system-running

# Are all critical services running?
systemctl status docker sshd prometheus-node-exporter avahi-daemon

# Any failed units?
systemctl --failed

# Is persistence working?
mountpoint /persistent
mountpoint /var/lib/docker
mountpoint /etc/ssh

# Is the Grist container running?
docker ps

# Can you still reach the machine from other hosts?
# (test from a different terminal)
ping ghost.local
```

> **Why this matters:** The `test` stage is your safety net. The new config is running live — you can poke at it, test services, verify networking. But if anything is broken, a simple `reboot` rolls everything back to the last known-good configuration.

**Recovery if something breaks:**

```bash
# Option A: reboot (restores previous config automatically)
ssh root@<ip> reboot

# Option B: if SSH is dead, physically power cycle the machine
# It will boot back to the previous config
```

**Decision point:**
- Everything works → proceed to Stage 3
- Something broken → reboot to roll back, fix config, start over from Stage 1

---

## Stage 3: `switch`

**What it does:** Activates the new configuration **and** adds it to the bootloader as the default. This is the new system from now on.

```bash
nixos-rebuild switch \
  --flake .#ghost \
  --target-host root@<ip>
```

**What happens on the target:**

1. The new system closure is activated (same as `test`)
2. The bootloader is updated — this config is now the boot default
3. The previous generation is kept as a fallback in the boot menu

> **Why this matters:** After `switch`, a reboot will boot into the *new* config, not the old one. This is the point of no return for the current boot cycle. However, NixOS keeps previous generations in the bootloader, so you can always select an older generation from the boot menu if needed.

**Post-deploy verification:**

```bash
# Confirm the running system matches the expected generation
nixos-rebuild list-generations --flake .#ghost --target-host root@<ip> | head -5

# Verify the system is fully healthy
ssh root@<ip> "systemctl is-system-running && systemctl --failed"
```

---

## Using the Justfile

The `deploy` recipe wraps `nixos-rebuild switch`:

```bash
# Default target (edit the justfile or override inline)
just deploy target=root@<ip>

# With extra args
just deploy target=root@<ip> -- --dry-activate
```

For the full three-stage workflow:

```bash
# Stage 1
nixos-rebuild dry-activate --flake .#ghost --target-host root@<ip>

# Stage 2
nixos-rebuild test --flake .#ghost --target-host root@<ip>

# Stage 3 (or use: just deploy target=root@<ip>)
nixos-rebuild switch --flake .#ghost --target-host root@<ip>
```

---

## Quick Reference

| Stage | Activates? | Updates bootloader? | Survives reboot? | Risk |
|---|---|---|---|---|
| `dry-activate` | ❌ | ❌ | N/A | **Zero** |
| `test` | ✅ | ❌ | ❌ (rolls back) | **Low** |
| `switch` | ✅ | ✅ | ✅ (new default) | **Medium** |

---

## Common Mistakes

| Mistake | Consequence | Prevention |
|---|---|---|
| Skipping `dry-activate` | Surprise service restarts, possible lockout | Always run `dry-activate` first |
| Running `switch` without `test` | Bad config becomes boot default | Always `test` first, verify, then `switch` |
| Changing SSH config without testing | Locked out of remote machine | `test` first — reboot recovers |
| Deploying without building locally | Slow builds on target, wasted time | Run `just test` locally first |
| Ignoring failed units after deploy | Silent service outages | Always check `systemctl --failed` |

---

## Ghost-Specific Notes

- **tmpfs root**: A reboot always clears non-persistent state. This makes `test` especially safe — a reboot is a clean rollback to the previous generation.
- **Preservation bind mounts**: After deploy, always verify `mountpoint /persistent` and key directories like `/var/lib/docker`, `/etc/ssh`. If these aren't mounted, persistent data is invisible.
- **Grist env file**: The Grist container needs `/var/lib/grist/env` to exist on the target. If it's missing, the service will fail (this is expected on first deploy — create the file manually).
- **Secrets**: Secrets live in `/var/lib/grist/env` on the target, not in the Nix config or git. They are not affected by deploys.
