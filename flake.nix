{
  description = "Ghost: Bare Minimum Docker Host in RAM with Persistence";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";
    polarbear.url = "github:kodicw/polarbear";
    nxbooter.url = "github:kodicw/nxbooter";
    nxbooter.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    preservation.url = "github:nix-community/preservation";
  };

  outputs = { self, nixpkgs, polarbear, nxbooter, disko, preservation, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      nixosConfigurations = {
        ghost = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./default.nix
            ./hardware.nix
            ./disko.nix
            disko.nixosModules.disko
            preservation.nixosModules.preservation
            nxbooter.nixosModules.default
            polarbear.nixosModules.users.root
            polarbear.nixosModules.users.charles
          ];
        };

        ghost-iso = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ./default.nix
            ./hardware.nix
            preservation.nixosModules.preservation # Add it here too
            polarbear.nixosModules.users.root
            polarbear.nixosModules.users.charles
            # Override for ISO
            ({ lib, ... }: {
              fileSystems."/".device = lib.mkForce "nixos-iso";
              preservation.enable = lib.mkForce false;
            })
          ];
        };
      };

      packages.${system} = {
        nxbooter = nxbooter.lib.buildNxbooter {
          inherit pkgs;
          systemConfig = self.nixosConfigurations.ghost;
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [ pkgs.just ];
      };
    };
}
