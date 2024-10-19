{
  description = "Common NixOS config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";

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
      # use /home-manager to get stable release
      url = "github:nix-community/home-manager";
      #url = "https://github.com/nix-community/home-manager/archive/release-24.05.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    nix-darwin,
    flake-checker,
    home-manager,
    ...
  } @ inputs: let
    inherit (self) outputs;
    inherit (builtins) listToAttrs;

    supportedSystems = [
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
      #"x86_64-darwin"
    ];

    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

    commonModules = [
      ./modules/common.nix
    ];

    mkSystem = {
      system,
      modules ? [],
    }:
      nixpkgs.lib.nixosSystem {
        #inherit system;
        specialArgs = {inherit inputs outputs;};
        modules =
          [
            # import the overlays module
            (import ./overlays {inherit inputs;})

            # common modules
            # ...
          ]
          ++ modules;
      };

    hmHomesForUsers = hm: users: [
      hm
      {
        home-manager = {
          useGlobalPkgs = true;
          backupFileExtension = "backup";
          users = listToAttrs (map
            (uname: {
              name = uname;
              value = import ./per-user/${uname};
            })
            users);
        };
      }
    ];
  in {
    # Your custom packages
    # Accessible through 'nix build', 'nix shell', etc
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      import ./pkgs {inherit pkgs;});

    # custom packages and modificatios, exported as overlays
    overlays = import ./overlays {inherit inputs;};
    # overlays.default = final: prev: (import ./overlays inputs self) final prev;

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

    darwinConfigurations = let
      home-manager = inputs.home-manager.darwinModules.home-manager;
    in {
      comet = inputs.nix-darwin.lib.darwinSystem {
        specialArgs = {};
        modules =
          [
            ./per-host/comet
          ]
          ++ (hmHomesForUsers home-manager ["steve"])
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
        modules =
          [
            ./per-host/pangea
          ]
          ++ (hmHomesForUsers home-manager ["steve"])
          ++ commonModules;
      };

      fake = mkSystem {
        system = "x86_64-linux";
        modules =
          [
            ./per-host/fake
          ]
          ++ (hmHomesForUsers home-manager ["user"])
          ++ commonModules;
      };

      aster = mkSystem {
        system = "aarch64-linux";
        modules =
          [
            ./per-host/aster
          ]
          ++ (hmHomesForUsers home-manager ["steve"])
          ++ commonModules;
      };
    };
  };
}
