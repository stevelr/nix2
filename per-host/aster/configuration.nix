# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  config,
  pkgs,
  lib,
  ...
}: let
  mkUsers = pkgs.myLib.mkUsers config.my.userids;
  mkGroups = pkgs.myLib.mkGroups config.my.userids;
in {
  imports = [
    # Include the results of the hardware scan.
    ../../services
    ./hardware-configuration.nix
    #./gitea.nix
  ];

  config = {
    my = {
      hostName = "aster";
      hostDomain = "comet.pasilla.net";
      localDomain = "cnet";

      pre.subnets = {
        # enp0s1
        "aster-lan0" = {
          name = "lan0";
          domain = "comet.pasilla.net";
          gateway = "10.135.1.1";
        };

        # internal bridges
        "container-br0" = {
          name = "br0";
          gateway = "10.55.0.1";
          dhcp.enable = true;
        };
      };

      containers = {
        gitea = {
          enable = true;
          name = "gitea";
          bridge = "container-br0";
          address = "10.55.0.16";
          proxyPort = 3000;
          settings = {
            ssh = 3022;
            hostSsh = 3022;
          };
        };

        # clickhouse.enable = false;
        # grafana.enable = false;
        # unbound.enable = false;
        # nettest.enable = false;
        # nginx.enable = false;
        # "empty-static".enable = false;

        vault = {
          enable = true;
          name = "vault";
          bridge = "container-br0";
          address = "10.55.0.17";
          proxyPort = config.my.ports.vault.port;
          settings = {
            enable = true;
            # internal port
            #apiPort = 8200;
            clusterPort = 8201;
            clusterName = "aster.pasilla.net";
            # external api address
            apiAddr = "https://aster.pasilla.net";
            # external cluster address
            clusterAddr = "https://aster.pasilla.net:8201";
            # server log level: trace,debug,info.warn,err
            logLevel = "info"; #
            storagePath = "/var/lib/vault";
          };
        };
      };
    };

    nix.settings.experimental-features = ["nix-command" "flakes"];

    # Bootloader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # use systemd-networkd, rather than the legacy systemd.network
    systemd.network.enable = true;

    systemd.network.networks."50-br0" = let
      cfg = config.my.pre.subnets."container-br0";
    in {
      matchConfig.Name = cfg.name;
      address = ["${cfg.gateway}/${toString cfg.prefixLen}"];
      #networkConfig.Address = "10.55.0.1/24";
    };
    systemd.network.netdevs."20-br0" = {
      enable = true;
      netdevConfig = {
        Name = "br0";
        Kind = "bridge";
      };
    };

    # Set your time zone.
    time.timeZone = "America/Los_Angeles";

    # Select internationalisation properties.
    i18n.defaultLocale = "en_US.UTF-8";

    i18n.extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };

    # Enable the X11 windowing system.
    services.xserver.enable = true;

    # Enable the Budgie Desktop environment.
    services.xserver.displayManager.lightdm.enable = true;
    services.xserver.desktopManager.budgie.enable = true;

    # Configure keymap in X11
    services.xserver.xkb = {
      layout = "us";
      variant = "";
    };

    # Enable CUPS to print documents.
    services.printing.enable = false;

    # Enable sound with pipewire.
    hardware.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = false;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      # If you want to use JACK applications, uncomment this
      #jack.enable = true;

      # use the example session manager (no others are packaged yet so this is enabled by default,
      # no need to redefine it in your config for now)
      #media-session.enable = true;
    };

    # Enable touchpad support (enabled default in most desktopManager).
    # services.xserver.libinput.enable = true;

    # Define a user account. Don't forget to set a password with ‘passwd’.
    users.users = lib.recursiveUpdate (mkUsers []) {
      steve = {
        #uid = config.my.userids.steve.uid;
        #isNormalUser = true;
        #description = "Steve";
        group = "users";
        extraGroups = ["networkmanager" "wheel" "audio" "video"];
        #shell = "${pkgs.zsh}/bin/zsh";
      };
      # vault = {
      #   isSystemUser = true;
      #   uid = config.my.userids.vault.uid;
      #   group = "vault";
      # };
    };
    users.groups = mkGroups [];
    # {
    #   exporters.gid = config.my.userids.exporters.gid;
    #   vault.gid = config.my.userids.vault.gid;
    # };

    programs.firefox.enable = true;
    programs.zsh.enable = true;

    # Allow unfree packages
    #nixpkgs.config.allowUnfree = true;
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [
        "vault-bin"
      ];

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
      starship
      tailscale
      vim
      wget
      wireguard-tools
    ];

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    # programs.mtr.enable = true;
    # programs.gnupg.agent = {
    #   enable = true;
    #   enableSSHSupport = true;
    # };

    # List services that you want to enable:

    # Enable the OpenSSH daemon.
    services.openssh.enable = true;

    services.tailscale = {
      enable = false;
      port = 41641;
      useRoutingFeatures = "both";
    };

    # services.nats = {
    #   enable = true;
    #   port = 4222;
    #   dataDir = "/var/lib/nats";
    #   serverName = "cometvm";
    #   jetstream = true;
    #   # settings = { } # json settings
    # };

    networking = {
      hostName = "aster"; # Define your hostname.
      wireless.enable = false;

      networkmanager.enable = true;

      firewall = {
        enable = true;
        allowedTCPPorts = [22 4222 41641];
      };
      nftables = {
        enable = true;
        tables."container-fwd" = {
          name = "container-fwd";
          enable = true;
          family = "ip";
          content = ''
            # forwarding rule from containers out to WAN
            chain post {
              type nat hook postrouting priority srcnat; policy accept;
              ip saddr 10.55.0.0/24 ip daddr != 10.55.0.0/24 masquerade
            }
          '';
        };
      };
    };

    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    system.stateVersion = "24.05"; # Did you read the comment?
  };
}
