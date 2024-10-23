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

    users.users = {
      user = {
        uid = config.const.userids.user.uid;
        isNormalUser = true;
        group = "users";
        shell = "${pkgs.zsh}/bin/zsh";
      };
    };
    users.groups.exporters = {
      gid = lib.mkForce config.const.userids.exporters.gid;
    };

    # Allow specific unfree packages
    # nixpkgs.config.allowUnfreePredicate = pkg:
    #   builtins.elem (lib.getName pkg) [
    #     "vault-bin"
    #   ];

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    environment.systemPackages = with pkgs; [
      bind.dnsutils # dig
      curl
      git
      helix
      just
      lsof
      ripgrep
      vim
      wget
    ];

    programs.zsh.enable = true;
    # Enable the OpenSSH daemon.
    services.openssh.enable = true;
    # Eneable ntp client
    services.chrony = {
      enable = true;
      serverOption = "offline"; # "offline" if machine is frequently offline
      servers = config.const.ntpServers.us;
    };
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
      networking.timeServers = config.const.ntpServers.global;
    };
    system.stateVersion = "24.05";
  };
}
