{ config, pkgs, lib, ... }:

{
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
    defaultNetwork.settings.dns_enabled = true;
    autoPrune.enable = true;
  };

  users.users.charles.extraGroups = [ "podman" ];
  users.users.root.extraGroups = [ "podman" ];
}
