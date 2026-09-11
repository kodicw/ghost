{ config, pkgs, lib, ... }:

{
  networking.hostName = "ghost-fs";

  # SeaweedFS Configuration
  services.seaweedfs = {
    enable = true;
    master = {
      enable = true;
      address = "127.0.0.1"; # Bind to localhost for internal cluster communication
    };
    volume = {
      enable = true;
      # Mount points for the 3 dedicated disks
      dirs = [ "/mnt/disk1" "/mnt/disk2" "/mnt/disk3" ];
      maxVolumes = 100; # Adjust based on disk size and needs
    };
  };

  # Storage: Mount 3 separate block devices
  # Using fileSystems as requested. 
  # Note: In a real scenario, use UUIDs instead of /dev/sdx for reliability.
  fileSystems."/mnt/disk1" = {
    device = "/dev/sdb";
    fsType = "ext4";
    options = [ "defaults" "noatime" ];
  };

  fileSystems."/mnt/disk2" = {
    device = "/dev/sdc";
    fsType = "ext4";
    options = [ "defaults" "noatime" ];
  };

  fileSystems."/mnt/disk3" = {
    device = "/dev/sdd";
    fsType = "ext4";
    options = [ "defaults" "noatime" ];
  };

  # Open firewall ports for SeaweedFS
  # networking.firewall.allowedTCPPorts is already handled by the seaweedfs module
  # but we might want to ensure other ports are open if needed.
}
