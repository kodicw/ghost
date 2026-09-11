{ config, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # PERFORMANCE: OS Root in RAM
  fileSystems."/" = lib.mkDefault {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "size=3G"
      "mode=755"
    ];
  };

  fileSystems."/nix" = {
    device = lib.mkForce "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=nix" "compress=zstd" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/persistent" = {
    device = lib.mkForce "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=persistent" "compress=zstd" "noatime" ];
    neededForBoot = true;
  };

  # Generic Bootloader (for persistent install)
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.systemd-boot.graceful = true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  boot.initrd.supportedFilesystems = [ "btrfs" ];
  boot.initrd.systemd.enable = true;
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "e1000e"
    "r8169"
    "igb"
  ];

  boot.initrd.kernelModules = [ "btrfs" ];
  boot.kernelModules = [ "kvm-intel" ];
  
  hardware.enableRedistributableFirmware = true;
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
