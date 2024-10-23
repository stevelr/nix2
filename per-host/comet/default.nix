# per-host/comet/default.nix
{
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  hostname = "comet";
in {
  environment.systemPackages =
    (with pkgs; [
      inetutils # ping, traceroute, ...
      tailscale
      markdown-oxide
      _1password # 1password cli
      yubikey-manager
      yubikey-personalization
      age-plugin-yubikey
      #yubikey-personalization-gui # broken (last checked: 10-10-2024)
    ])
    ++ (lib.optionals isDarwin (with pkgs; [
      ## darwin-specifix config
      darwin.iproute2mac
      unixtools.nettools # arp, hostname, ifconfig, netstat, route
      #unixtools.getopt
    ]));

  environment.pathsToLink = [
    "/share/zsh" # completion for system packages e.g., systemd
  ];

  programs.zsh = {
    enable = true;
    enableFzfGit = true; # fzf keybindings for C-g git browsing
    enableFzfHistory = true; # fzf keybindings for C-r history search
  };

  homebrew = lib.optionalAttrs isDarwin {
    enable = true;
    # setting onActivation.upgrade=true upgrades outdated formulae on nix-darwin activation
    onActivation.upgrade = true;
    # when using nix to manage homebrew, set this to "cleanup" or "zap"
    onActivation.cleanup = "zap";
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

  services.nix-daemon.enable = true;

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "1password-cli"
      "vault-bin"
    ];

  users.users.steve = {
    name = "steve";
    home = "/Users/steve";
  };

  networking = {
    #computerName = hostname;
    hostName = hostname;
  };

  system.defaults.trackpad.Clicking = true; # tap to click
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true; # make caps lock key act as Ctrl
  };
  # use touch id instead of sudo password
  security.pam.enableSudoTouchIdAuth = true;

  # important: before changing, review nix-darwin changelog
  system.stateVersion = 5;
  #system.nixpkgsRelease = "24.11";

  nix = {
    # Necessary for using flakes on this system.
    settings.experimental-features = "nix-command flakes";

    # nix package instance: pkgs.nixVersions.{stable, latest, git}
    package = pkgs.nixVersions.latest;

    ## garbage-collection & other cleanup
    ##
    ## Manually:
    ##   sudo nix-collect-garbage -d     # remove old packages
    ##   sudo nix-store --optimise       # remove duplicates

    # remove duplicates
    settings.auto-optimise-store = true;
    # gc weekly, on Sunday
    gc.interval = [
      {
        Hour = 12;
        Minute = 0;
        Weekday = 0;
      }
    ];
    gc.automatic = true;
    # optimize weekly, on Sunday
    optimise.automatic = true;
    optimise.interval = [
      {
        Hour = 13;
        Minute = 0;
        Weekday = 0;
      }
    ];
  };
}
