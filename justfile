host := env_var_or_default("HOST", "root@192.168.1.100")
disk_device := env_var_or_default("DISK_DEVICE", "/dev/sda")

# Default recipe to show available targets
default:
    @just --list

# Check flake evaluation
check:
    nix flake check

# Build the netboot image and start the PXE server
netboot:
    sudo nix run .#nxbooter

# Build the ISO image
build-iso:
    nix build .#nixosConfigurations.ghost-iso.config.system.build.isoImage

# Flash the generated ISO to a USB device
flash-usb device="/dev/sda":
    @echo "WARNING: This will format the device {{device}}. Are you sure? [y/N]"
    @read ans && [ $${ans:-N} = y ]
    sudo dd if=$(readlink -f result/iso/nixos-*.iso) of={{device}} bs=4M status=progress

# Remote deployment using nixos-anywhere
anywhere:
    nix run github:nix-community/nixos-anywhere -- --flake .#ghost --target-host {{host}} --disk-encryption-keys /tmp/keys /tmp/keys
