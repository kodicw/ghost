{ config, pkgs, lib, ... }:

let
  cfg = config.services.seaweedfs;
in
{
  options.services.seaweedfs = {
    enable = lib.mkEnableOption "SeaweedFS services";
    
    master = {
      enable = lib.mkEnableOption "SeaweedFS Master service";
      address = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Address for the Master to bind to.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 9333;
        description = "Port for the Master to listen on.";
      };
    };

    volume = {
      enable = lib.mkEnableOption "SeaweedFS Volume service";
      port = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Port for the Volume server to listen on.";
      };
      dirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Directories to store volumes.";
      };
      maxVolumes = lib.mkOption {
        type = lib.types.int;
        default = 7;
        description = "Maximum number of volumes for each directory.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.seaweedfs ];

    # Open firewall ports
    networking.firewall.allowedTCPPorts = 
      (lib.optional cfg.master.enable cfg.master.port) ++
      (lib.optional cfg.volume.enable cfg.volume.port);

    # Dedicated user for SeaweedFS
    users.users.seaweedfs = {
      isSystemUser = true;
      group = "seaweedfs";
      description = "SeaweedFS daemon user";
    };
    users.groups.seaweedfs = {};

    # Master Service
    systemd.services.seaweedfs-master = lib.mkIf cfg.master.enable {
      description = "SeaweedFS Master Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.seaweedfs}/bin/weed master -ip=${cfg.master.address} -port=${toString cfg.master.port}";
        Restart = "on-failure";
        RestartSec = 5;
        User = "seaweedfs";
        Group = "seaweedfs";
        
        # Hardening
        ProtectSystem = "full";
        ProtectHome = "true";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectControlGroups = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictRealtime = true;
        SystemCallFilter = [ "@system-service" "~@privileged" ];
      };
    };

    # Volume Service
    systemd.services.seaweedfs-volume = lib.mkIf cfg.volume.enable {
      description = "SeaweedFS Volume Server";
      after = [ "network.target" "seaweedfs-master.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.seaweedfs}/bin/weed volume -mserver=${cfg.master.address}:${toString cfg.master.port} -port=${toString cfg.volume.port} -dir=${lib.concatStringsSep "," cfg.volume.dirs} -max=${toString cfg.volume.maxVolumes}";
        Restart = "on-failure";
        RestartSec = 5;
        User = "seaweedfs";
        Group = "seaweedfs";

        # Hardening
        ProtectSystem = "full";
        ProtectHome = "true";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectControlGroups = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictRealtime = true;
        SystemCallFilter = [ "@system-service" "~@privileged" ];
        
        # Ensure it can write to the mounted disks
        ReadWritePaths = cfg.volume.dirs;
      };
    };
    
    # Ensure storage directories have correct ownership
    systemd.tmpfiles.rules = map (dir: "d ${dir} 0750 seaweedfs seaweedfs - -") cfg.volume.dirs;
  };
}
