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

  # Persistence Mount
  fileSystems."/persistent".neededForBoot = true;

  # Generic Bootloader (for persistent install)
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

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
  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];
  
  hardware.enableRedistributableFirmware = true;
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
