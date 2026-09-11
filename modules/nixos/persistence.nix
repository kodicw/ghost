{ config, lib, ... }:

{
  # PERSISTENCE: Setup what stays across reboots
  preservation = {
    enable = lib.mkDefault true;
    preserveAt."/persistent" = {
      directories = [
        "/var/lib/docker"
        "/var/lib/portainer"
        "/var/lib/tailscale"
        "/var/lib/nixos"
        "/var/lib/systemd"
        "/var/log"
        "/etc/NetworkManager/system-connections"
        "/opt"
        { directory = "/etc/ssh"; inInitrd = true; }
      ];
      files = [
        { file = "/etc/machine-id"; inInitrd = true; }
      ];
    };
  };
}
