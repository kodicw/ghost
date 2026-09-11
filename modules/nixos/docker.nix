{ config, pkgs, lib, ... }:

{
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
}
