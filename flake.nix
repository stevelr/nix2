{
  description = "Common NixOS config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # You can access packages and modules from different nixpkgs revs
    # at the same time.
    # If nixpkgs is stable, "pkgs.unstable" is added as an overlay, to make both available.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # Also see the 'unstable-packages' overlay at 'overlays/default.nix'.

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

      commonModules = [
        ./modules/common.nix
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
          #specialArgs = {pkgs = nixpkgs;};
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
        comet = inputs.nix-darwin.lib.darwinSystem {
          specialArgs = {
            hostname = "comet";
          };
          modules =
            [
              ./per-host/comet
              home-manager
              {
                home-manager = {
                  extraSpecialArgs = {
                    hostname = "comet";
                    username = "steve";
                  };
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  users."steve" = import ./per-user/steve;
                };
              }
            ]
            ++ commonModules;
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
          modules =
            [
              ./per-host/pangea
            ]
            ++ commonModules;
        };

        aster = mkSystem {
          system = "aarch64-linux";
          hostname = "aster";
          modules =
            [
              ./per-host/aster
              home-manager
              {
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  backupFileExtension = "backup";
                  users.steve = import ./per-user/steve;
                };

                # Optionally, use home-manager.extraSpecialArgs to pass
                # arguments to home.nix
              }
            ]
            ++ commonModules;
        };
      };
    };
}
