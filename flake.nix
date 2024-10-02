{
  description = "Common NixOS config";

  inputs = {
    # nixos-24.05 branch
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

    # You can access packages and modules from different nixpkgs revs
    # at the same time. Here's an working example:
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # Also see the 'unstable-packages' overlay at 'overlays/default.nix'.

    flake-checker = {
      url = "https://flakehub.com/f/DeterminateSystems/flake-checker/*";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {self, ...} @ inputs:
    with inputs; let
      # Supported systems for your flake packages, shell, etc.
      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
        "aarch64-darwin"
        #"x86_64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      mkPkgsFor = forAllSystems (system:
        import ./pkgs {
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          inherit system;
        });

      mkSystem = {
        system,
        hostname,
        modules ? [],
      }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {inherit inputs;};
          modules =
            [
              # import the overlays module
              (import ./overlays)

              # common modules
              # ...
            ]
            ++ modules;
        };
    in {
      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (
        system:
          with mkPkgsFor.${system}; {
            inherit
              hello-custom
              ;
          }
      );

      overlays.default = final: prev: (import ./overlays inputs self) final prev;

      # Formatter for your nix files, available through 'nix fmt'
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nil);

      # reusable modules - include each subdirectory
      nixosModules = builtins.listToAttrs (
        map
        (name: {
          inherit name;
          value = import (./modules + "/${name}");
        })
        (builtins.attrNames (builtins.readDir ./modules))
      );

      # Reusable home-manager modules you might want to export
      # These are usually stuff you would upstream into home-manager
      #homeManagerModules = import ./modules/home-manager;

      darwinConfigurations = let
        home-manager = inputs.home-manager.darwinModules.home-manager;
      in {
        comet = nix-darwin.lib.darwinSystem {
          specialArgs = {
            hostname = "comet";
          };
          modules = [
            ({...}: {
              nixpkgs.hostPlatform = "aarch64-darwin";
              users.users.steve = {
                name = "steve";
                home = "/Users/steve";
              };
            })
            ./configuration.nix
            home-manager
            {
              home-manager = {
                extraSpecialArgs = {
                  inherit (cfg) hostname username;
                };
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${cfg.username} = import ./home.nix;
              };
            }
          ];
        };
      };

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations = let
        home-manager = inputs.home-manager.nixosModules.home-manager;
      in {
        pangea = mkSystem {
          system = "x86_64-linux";
          hostname = "pangea";
          modules = [
            ./per-host/pangea
          ];
        };

        aster = mkSystem {
          system = "aarch64-linux";
          hostname = "aster";
          modules = [
            ./per-host/aster/configuration.nix
            home-manager
            {
              home-manager = {
                extraSpecialArgs = {
                  hostname = "aster";
                };
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "backup";
                users.steve = import ./per-user/steve;
              };

              # Optionally, use home-manager.extraSpecialArgs to pass
              # arguments to home.nix
            }
          ];
        };
      };
    };
}
