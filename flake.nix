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

  outputs =
    {
      self,
      nixpkgs,
      polarbear,
      nxbooter,
      disko,
      preservation,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      nixosModules = {
        core = ./modules/nixos/core.nix;
        persistence = ./modules/nixos/persistence.nix;
        docker = ./modules/nixos/docker.nix;
        monitoring = ./modules/nixos/monitoring.nix;
        networking = ./modules/nixos/networking.nix;
        netboot = ./modules/nixos/netboot.nix;
        grist = ./modules/nixos/grist.nix;
        seaweedfs = ./modules/nixos/seaweedfs.nix;

        # A bundle for easy consumption
        ghost = {
          imports = [
            self.nixosModules.core
            self.nixosModules.persistence
            self.nixosModules.docker
            self.nixosModules.monitoring
            self.nixosModules.networking
            # self.nixosModules.netboot
            self.nixosModules.grist
          ];
        };

        ghost-storage = {
          imports = [
            self.nixosModules.core
            self.nixosModules.persistence
            self.nixosModules.monitoring
            self.nixosModules.networking
            self.nixosModules.seaweedfs
          ];
        };
      };

      nixosConfigurations = {
        ghost = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            self.nixosModules.ghost
            ./hardware.nix
            ./disko.nix
            disko.nixosModules.disko
            preservation.nixosModules.preservation
            nxbooter.nixosModules.default
            polarbear.nixosModules.users.root
            polarbear.nixosModules.users.charles
          ];
        };

        ghost-fs = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            self.nixosModules.ghost-storage
            ./hosts/ghost-fs.nix
            ./hardware.nix
            ./disko.nix
            disko.nixosModules.disko
            preservation.nixosModules.preservation
            polarbear.nixosModules.users.root
            polarbear.nixosModules.users.charles
          ];
        };

        ghost-netboot = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            self.nixosModules.ghost
            self.nixosModules.netboot
            ./hardware.nix
            preservation.nixosModules.preservation
            polarbear.nixosModules.users.root
            polarbear.nixosModules.users.charles
          ];
        };

        ghost-iso = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            self.nixosModules.ghost
            ./hardware.nix
            preservation.nixosModules.preservation
            polarbear.nixosModules.users.root
            polarbear.nixosModules.users.charles
            (
              { lib, ... }:
              {
                fileSystems."/".device = lib.mkForce "nixos-iso";
                preservation.enable = lib.mkForce false;
              }
            )
          ];
        };
      };

      packages.${system} = {
        nxbooter = nxbooter.lib.buildNxbooter {
          inherit pkgs;
          systemConfig = self.nixosConfigurations.ghost-netboot;
        };
      };

      checks.${system} = {
        persistence = import ./tests/persistence.nix {
          inherit self pkgs preservation;
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          # Task runner
          just

          # NixOS deployment
          nixos-rebuild

          # Infrastructure
          opentofu

          # Configuration management
          ansible
          ansible-lint
          sshpass

          # OpenSpec (spec-driven workflow)
          nodePackages.nodejs
        ];

        shellHook = ''
          # Make npx-installed tools available
          export PATH="$HOME/.npm-global/bin:$PATH"

          echo "👻 Ghost dev shell"
          echo "   just          — run 'just' to see all commands"
          echo "   nix flake check — validate the flake"
          echo ""
        '';
      };
    };
}
