# Ghost — Ansible Automation

Adhoc configuration management for Ghost-based deployments, layered on top of NixOS.

## Layout

```
ansible/
├── ansible.cfg
├── requirements.yml                     # community.docker collection
├── group_vars/all.yml                   # Global defaults
│
├── inventory/production/
│   └── <client>/                        # One folder per client
│       ├── hosts.yml                    # Hosts + group membership
│       ├── group_vars/all.yml           # Client vars (references vault)
│       ├── group_vars/vault.yml         # 🔒 Encrypted secrets
│       └── host_vars/<host>.yml         # Per-host overrides
│
├── playbooks/
│   ├── site.yml              # Full orchestrator: common → dockhand → grist → health
│   ├── dockhand.yml          # Unified lifecycle: present/stopped/restarted/updated/…
│   ├── grist.yml             # Unified lifecycle: present/restarted/backed_up/info/…
│   ├── health-check.yml      # Standalone health check
│   └── backup.yml            # Standalone backup
│
└── roles/
    ├── common/               # Baseline: packages, Docker service, health checks
    ├── dockhand/             # Full lifecycle: 12 states
    └── grist/                # Full lifecycle: 10 states (NixOS-aware)
```

## State-based lifecycle

Every role uses a `_state` variable that dispatches to the right task file:

### Dockhand states (`dockhand_state`)

| State | Action |
|---|---|
| `present` (default) | Ensure running, deploy if absent |
| `started` | Start if stopped |
| `stopped` | Graceful stop |
| `restarted` | Stop then start |
| `updated` | Pull new image + recreate |
| `rolled_back` | Revert to previous image |
| `backed_up` | Snapshot volume + prune old |
| `restored` | Restore volume from snapshot |
| `logs` | Fetch recent container logs |
| `info` | Detailed status report |
| `absent` | Remove container + volume |

### Grist states (`grist_state`)

| State | Action |
|---|---|
| `present` (default) | Ensure running; bootstrap via API if first-run |
| `started` | Start if stopped |
| `stopped` | Graceful stop |
| `restarted` | Stop then start |
| `updated` | Pull new image + recreate *(only if not NixOS-managed)* |
| `backed_up` | Snapshot data dir + export docs via API |
| `restored` | Restore data dir from snapshot |
| `logs` | Fetch recent container logs |
| `info` | Detailed status report |
| `absent` | Remove container + data *(only if not NixOS-managed)* |

## Boundary with NixOS

| Layer | Managed by |
|---|---|
| OS, kernel, tmpfs | NixOS |
| Docker daemon, Tailscale, firewall | NixOS |
| Grist container (base definition) | NixOS (`grist.nix`) |
| Grist bootstrap & API config | **Ansible** |
| Grist lifecycle (restart, backup, logs) | **Ansible** (NixOS-aware) |
| Dockhand container | **Ansible** (full lifecycle) |
| Health checks & adhoc ops | **Ansible** |

## Usage

```bash
# Install collections
ansible-galaxy collection install -r requirements.yml

# Encrypt vault (first time)
ansible-vault encrypt inventory/production/ghost/group_vars/vault.yml

# ── Lifecycle commands ──────────────────────────

# Deploy everything (default: present)
ansible-playbook -i inventory/production/ghost playbooks/site.yml --ask-vault-pass

# Check dockhand status
ansible-playbook -i inventory/production/ghost playbooks/dockhand.yml \
  -e dockhand_state=info

# Restart dockhand
ansible-playbook -i inventory/production/ghost playbooks/dockhand.yml \
  -e dockhand_state=restarted

# Update dockhand to specific tag
ansible-playbook -i inventory/production/ghost playbooks/dockhand.yml \
  -e dockhand_state=updated \
  -e dockhand_update_tag=fnsys/dockhand:v2

# Rollback dockhand
ansible-playbook -i inventory/production/ghost playbooks/dockhand.yml \
  -e dockhand_state=rolled_back

# Backup both services
ansible-playbook -i inventory/production/ghost playbooks/backup.yml

# Grist info
ansible-playbook -i inventory/production/ghost playbooks/grist.yml \
  -e grist_state=info

# Grist logs
ansible-playbook -i inventory/production/ghost playbooks/grist.yml \
  -e grist_state=logs -e grist_log_lines=100

# Grist restart (works even on NixOS-managed)
ansible-playbook -i inventory/production/ghost playbooks/grist.yml \
  -e grist_state=restarted

# Health check only
ansible-playbook -i inventory/production/ghost playbooks/health-check.yml

# Add a new client
cp -r inventory/production/ghost inventory/production/<new-client>
# Edit hosts.yml, populate vault.yml, then encrypt
ansible-vault encrypt inventory/production/<new-client>/group_vars/vault.yml
```

## Vault secrets

```bash
# Decrypt / edit / encrypt
ansible-vault decrypt inventory/production/ghost/group_vars/vault.yml
ansible-vault encrypt inventory/production/ghost/group_vars/vault.yml
```
