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
anywhere target=host *args:
    nix run github:nix-community/nixos-anywhere -- --flake .#ghost --target-host {{target}} {{args}}
