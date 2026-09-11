{ config, pkgs, lib, ... }:

{
  # PERFORMANCE: zRAM
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
  
  boot.tmp.useTmpfs = true;
  boot.tmp.cleanOnBoot = true;

  # Environment setup
  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    zellij
    neovim
    wget
    ipmitool
  ];

  # IPMI support
  boot.kernelModules = [ "ipmi_si" "ipmi_devintf" "ipmi_msghandler" ];

  services.openssh.enable = true;
  services.getty.autologinUser = lib.mkForce "root";

  # Stop systemd from trying to "commit" the machine-id to disk
  # since the preservation module is already handling the persistence.
  systemd.services.systemd-machine-id-commit.enable = false;
  systemd.services.systemd-machine-id-commit.unitConfig.ConditionPathExists = "!/etc/machine-id";

  system.stateVersion = "25.11";
}
