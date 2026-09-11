{ config, lib, ... }:

{
  networking.hostName = lib.mkDefault "ghost";
  networking.firewall.allowedTCPPorts = [ 22 9000 9323 ];
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  services.tailscale.enable = true;

  # mDNS/Avahi
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };
}
