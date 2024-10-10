{
  pkgs,
  lib,
  hostname,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
in {
  services.nix-daemon.enable = true;
  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # ???
  nix.package = pkgs.nixVersions.git;

  # Used for backwards compatibility. please read the changelog
  # before changing: `darwin-rebuild changelog`.
  system.stateVersion = 4;

  users.users.steve = {
    name = "steve";
    home = "/Users/steve";
  };

  nixpkgs.hostPlatform = "aarch64-darwin";
  networking.hostName = hostname;

  environment.systemPackages =
    (with pkgs; [
      curl
      helix
      jq
      just
      less
      _1password # 1password cli
      ripgrep
      tailscale

      # yubikey-related
      yubikey-manager
      yubikey-personalization
      #yubikey-personalization-gui # broken (last checked: 10-10-2024)
      age-plugin-yubikey
    ])
    ++ (lib.optionals isDarwin (with pkgs; [
      ## darwin-specifix config
      darwin.iproute2mac
      unixtools.nettools # arp, hostname, ifconfig, netstat, route
      inetutils # ping, traceroute, ...
      #unixtools.getopt
    ]));

  environment.pathsToLink = [
    "/share/zsh" # completion for system packages e.g., systemd
  ];

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "1password-cli"
    ];

  homebrew = lib.optionalAttrs isDarwin {
    enable = true;
    taps = [
    ];
    brews = [
      "ca-certificates"
    ];
    casks = [
      "1password"
      "rectangle"
      "wezterm"
      "yubico-authenticator" # nixpkg is yubioauth-flutter but only supported on linux
    ];
  };

  # use touch id instead of sudo password
  security.pam.enableSudoTouchIdAuth = true;
}
