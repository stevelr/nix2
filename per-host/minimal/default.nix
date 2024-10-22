# per-host/fake/default.nix
# minimum configuration
#
{
  config,
  pkgs,
  lib ? pkgs.lib,
  ...
}: {
  imports = [
    ../../services
    #../../modules/zfs
    ./hardware-configuration.nix
  ];

  config = {
    my = {
      hostName = "minimal";
      hostDomain = "pasilla.net";
      localDomain = "pnet";
      pre.subnets = {};
    };

    # TODO: update this to match mounted files systems
    fileSystems = {
      "/".device = "/dev/hda1";
    };

    nix.settings.experimental-features = ["nix-command" "flakes"];

    # Bootloader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # enable ip forwarding - required for routing and for vpns
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # Set your time zone.
    time.timeZone = "America/Los_Angeles";

    # Time servers
    services.ntp = {
      enable = true;
      servers = [
        "0.us.pool.ntp.org"
        "1.us.pool.ntp.org"
        "2.us.pool.ntp.org"
        "3.us.pool.ntp.org"
      ];
    };

    users.users = {
      user = {
        isNormalUser = true;
        group = "users";
        shell = "${pkgs.zsh}/bin/zsh";
      };
    };
    users.groups.exporters = {
      gid = lib.mkForce config.const.userids.exporters.gid;
    };

    programs.zsh.enable = true;

    # Allow specific unfree packages
    # nixpkgs.config.allowUnfreePredicate = pkg:
    #   builtins.elem (lib.getName pkg) [
    #     "vault-bin"
    #   ];

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    environment.systemPackages = with pkgs; [
      curl
      git
      helix
      just
      jq
      lsof
      ripgrep
      vim
      wget
    ];

    # Enable the OpenSSH daemon.
    services.openssh.enable = true;

    # use systemd-networkd, rather than the legacy systemd.network
    systemd.network.enable = true;

    networking = {
      hostName = config.my.hostName;
      wireless.enable = false;
      useNetworkd = true;
      firewall = {
        enable = true;
        allowedTCPPorts = with config.const.ports; [ssh.port http.port];
      };
      nftables = {
        enable = true;
        checkRuleset = true;
      };
    };
    system.stateVersion = "24.05";
  };
}
