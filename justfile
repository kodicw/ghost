host := env_var_or_default("HOST", "root@192.168.1.100")
disk_device := env_var_or_default("DISK_DEVICE", "/dev/sda")

# Default recipe to show available targets
default:
    @just --list

# Check flake evaluation
check *args:
    nix flake check {{args}}

# Build the netboot image and start the PXE server
netboot *args:
    sudo nix run .#nxbooter -- {{args}}

# Build the ISO image
build-iso *args:
    nix build .#nixosConfigurations.ghost-iso.config.system.build.isoImage {{args}}

# Flash the generated ISO to a USB device
flash-usb device=disk_device:
    #!/usr/bin/env bash
    printf "WARNING: This will format the device {{device}}. Are you sure? [y/N] "
    read -r ans
    if [[ "$ans" =~ ^[yY]$ ]]; then
        sudo dd if=$(readlink -f result/iso/nixos-*.iso) of={{device}} bs=4M status=progress
    else
        echo "Aborted."
        exit 1
    fi

# Remote deployment using nixos-anywhere
anywhere target=host device=disk_device *args:
    nix run github:nix-community/nixos-anywhere -- --flake .#ghost --target-host {{target}} {{args}}

# Switch the configuration on a running system
deploy target="root@192.168.1.53" *args:
    nixos-rebuild switch --flake .#ghost --target-host {{target}} --sudo {{args}}

# Build the system configuration locally to check for errors
test:
    nix build .#nixosConfigurations.ghost.config.system.build.toplevel

# Run VM integration test: proves tmpfs root + persistent data across reboot
check-vm *args:
    nix build .#checks.x86_64-linux.persistence -L {{args}}

# ── GCP Infrastructure (OpenTofu) ────────────────────────────────

# Initialize OpenTofu with remote state
gcp-init:
    cd infra/gcp && tofu init -backend-config="bucket=ghost-tofu-state" -backend-config="prefix=gcp/ghost"

# Plan GCP infrastructure changes
gcp-plan:
    cd infra/gcp && tofu plan -out=tfplan

# Apply GCP infrastructure changes
gcp-apply:
    cd infra/gcp && tofu apply tfplan

# Format all OpenTofu files
gcp-fmt:
    cd infra/gcp && tofu fmt -recursive

# Validate OpenTofu configuration
gcp-validate:
    cd infra/gcp && tofu validate

# Show current GCP state
gcp-show:
    cd infra/gcp && tofu show

# List all GCP resources in state
gcp-state-list:
    cd infra/gcp && tofu state list

# Tear down all GCP infrastructure
gcp-destroy:
    cd infra/gcp && tofu destroy

# Show GCP output values
gcp-output:
    cd infra/gcp && tofu output
