{ config, lib, ... }:

{
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.grist = {
    image = "gristlabs/grist";
    ports = [ "8484:8484" ];
    volumes = [
      "/var/lib/grist:/persist"
    ];
    environment = {
      APP_HOME_URL = "http://ghost.local:8484";
      GRIST_SINGLE_ORG = "docs";
    };
    # Secrets are loaded at runtime from an env file outside the Nix store
    environmentFiles = [ "/var/lib/grist/env" ];
  };

  # Open the firewall for Grist
  networking.firewall.allowedTCPPorts = [ 8484 ];

  # Persistence for Grist data
  preservation.preserveAt."/persistent" = {
    directories = [
      "/var/lib/grist"
    ];
  };
}
