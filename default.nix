{ config, pkgs, lib, inputs, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/installer/netboot/netboot-minimal.nix"
  ];

  # PERSISTENCE: Setup what stays across reboots
  preservation = {
    enable = true;
    preserveAt."/persistent" = {
      directories = [
        "/var/lib/docker"
        "/var/lib/portainer"
        "/var/lib/tailscale"
        "/var/lib/nixos"
        "/var/lib/systemd"
        "/var/log"
        "/etc/ssh"
        "/etc/NetworkManager/system-connections"
        "/opt"
      ];
      files = [
        "/etc/machine-id"
      ];
    };
  };

  # Environment setup
  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    tmux
    vim
    wget
  ];

  # PERFORMANCE: zRAM
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
  
  boot.tmp.useTmpfs = true;
  boot.tmp.cleanOnBoot = true;

  # Services
  services.tailscale.enable = true;
  services.openssh.enable = true;

  # Docker
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
    daemon.settings = {
      metrics-addr = "0.0.0.0:9323";
      experimental = true;
    };
  };

  users.users.charles.extraGroups = [ "docker" ];
  users.users.root.extraGroups = [ "docker" ];

  # Monitoring
  services.prometheus.exporters = {
    node = {
      enable = true;
      port = 9000;
      enabledCollectors = [ "systemd" "tcpstat" ];
    };
  };

  networking.firewall.allowedTCPPorts = [ 22 9000 9323 ];
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  system.stateVersion = "25.11";
}
