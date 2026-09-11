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
    tmux
    vim
    wget
  ];

  services.openssh.enable = true;
  services.getty.autologinUser = lib.mkForce "root";

  system.stateVersion = "25.11";
}
