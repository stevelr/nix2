# per-host/aster/configuration.nix
#
{
  config,
  pkgs,
  lib,
  #  outputs,
  ...
}: let
  inherit (builtins) attrNames;
  inherit (lib.attrsets) filterAttrs;
  inherit (pkgs.myLib) tmpfiles;

  nginxIP = "10.55.0.15";
  mediaIP = "192.168.10.11";
  # where to forward incoming http traffic - either nginxIP or mediaIP
  activeHttp = mediaIP;
  hostDomain = "pasilla.net";
  fqdn = "aster.pasilla.net";

  mkUsers = pkgs.myLib.mkUsers config.const.userids;
  mkGroups = pkgs.myLib.mkGroups config.const.userids;

  ns101 = {
    name = "ns101"; # namespace name
    lanIface = "enp0s1"; # only used for port forwarding
    veNsIp4 = "192.168.10.11";
    veHostIp4 = "192.168.10.10";
    wgIp4 = "10.2.0.2"; # local (vpn client) interface ip in wg tunnel (dev is wg0)
    wgGateway = "10.2.0.1"; # other end of wg tunnel
    vpnDns = ["10.2.0.1"]; # dns server(s) for vpn clients
  };
in {
  imports = [
    ../../services
    ./hardware-configuration.nix
  ];

  config = {
    my = {
      hostName = "aster";
      hostDomain = hostDomain;
      localDomain = "pnet";

      # later converted to my.subnets
      pre.subnets = {
        # enp0s1
        "aster-lan0" = {
          name = "lan0";
          localDev = "enp0s1";
          domain = hostDomain;
          gateway = "10.135.1.1";
        };

        # internal bridges
        "container-br0" = {
          name = "br0";
          gateway = "10.55.0.1";
          domain = fqdn;
          dhcp.enable = true;
        };
      };

      services = {
        unbound = {
          enable = true;
          wanNet = "aster-lan0";
        };
        tailscale.enable = true;
        kea.enable = false;
      };

      # network namespaces with routing through wireguard vpn
      # each namespace requires a file /etc/router/NAMESPACE/wg.conf
      vpnNamespaces = {
        inherit ns101;
      };

      containers = {
        #
        nginx = {
          # it doesn't make sense to run nginx if we are also running media container
          enable = activeHttp == nginxIP;
          name = "nginx";
          bridge = "container-br0";
          address = nginxIP;
          settings = {
            subdomain = fqdn;

            # list of containers and services that we proxy
            # Don't include vault if we want vault to terminate tls.
            # Media services aren't here either: they have their own nginx
            backends = [];

            # bindmounts for certificates
            mounts = let
              # on aster, we have wildcard cert for all virtual hosts,
              # i.e., aster.pasilla.net and *.aster.pasilla.net
              wildcardCertPath = {hostPath = "/root/certs/${fqdn}";};
            in {
              "/var/local/www" = {hostPath = "/var/lib/www/${fqdn}";};
              "/etc/ssl/nginx/${fqdn}" = wildcardCertPath;
            };
          };
        };

        media = {
          enable = true;
          name = "media";
          bridge = "container-br0";
          address = "10.55.0.40";
          namespace = "ns101";
        };

        # nettest is used here for manual vpn testing
        nettest = {
          enable = true;
          name = "nettest";
          bridge = "container-br0";
          address = "10.55.0.20";
          namespace = "ns101"; # make it run inside this vpn namespace
        };

        # used for manual testing
        "vpn-sh" = {
          enable = true;
          name = "vpn-sh";
          bridge = "container-br0";
          namespace = "ns101";
        };

        # hashicorp vault for secrets
        vault = let
          apiPort = config.const.ports.vault.apiPort;
          clusterPort = config.const.ports.vault.clusterPort;
        in {
          enable = true;
          name = "vault";
          bridge = "container-br0";
          address = "10.55.0.17";
          proxyPort = apiPort;
          settings = {
            inherit apiPort clusterPort;
            enable = true;
            uiEnable = true;
            tls = {
              enable = true;
              chain = "/root/certs/vault.${fqdn}/fullchain1.pem";
              privkey = "/root/certs/vault.${fqdn}/privkey1.pem";
            };
            clusterName = fqdn;
            # external api address
            apiAddr = "https://vault.${fqdn}:${toString apiPort}";
            # external cluster address
            clusterAddr = "vault.${fqdn}:${toString clusterPort}";
            # server log level: trace,debug,info.warn,err
            logLevel = "info"; #
            storagePath = "/var/lib/vault";
          };
        };
      };

      # media server configuration
      media = {
        enable = true;
        namespace = "ns101";
        vpn = ns101;
        container = "media"; # reference media container above
        urlDomain = fqdn;
        services = with config.const.ports; {
          # defaults: { enable = true; user=<service name>; group=<group name>; };
          jellyfin.proxyPort = jellyfin.port;
          sonarr.proxyPort = sonarr.port;
          radarr.proxyPort = radarr.port;
          qbittorrent.proxyPort = qbittorrent.port;
          audiobookshelf.proxyPort = audiobookshelf.port;
          jackett.proxyPort = jackett.port;
          prowlarr.proxyPort = prowlarr.port;
        };
        staticSite = "/var/lib/media/www";
        # sshPort needs to be different from 22 to avoid conflicting with host's sshd
        sshPort = 2022;
        # will be opened in firewall (tcp & udp). must be set in qbittorrent settings
        btListenPort = 14641;
        storage = {
          hostBase = "/var/lib/media";
          localBase = "/media";
        };
        # security.sudo settings
        sudo = {
          enable = true;
          execWheelOnly = true;
        };
      };
    };

    nix.settings.experimental-features = ["nix-command" "flakes"];

    # Bootloader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # enable ip forwarding - required for routing and for vpns
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # use systemd-networkd, rather than the legacy systemd.network
    systemd.network.enable = true;

    systemd.network.networks."50-br0" = let
      cfg = config.my.subnets."container-br0";
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

    # For each normal user, give it its own sub-directories under /mnt/scratch/home/ and
    # /var/tmp/home/.  This is especially useful for a user to place large dispensable things that
    # it wants to be excluded from backups.
    systemd.tmpfiles.packages =
      tmpfiles.makeUserTmpdirPkgs
      (attrNames (filterAttrs (n: v: v.isNormalUser) config.users.users))
      "users"
      [
        "/var/tmp/home"
        "/mnt/scratch/home"
      ];

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

    users.users =
      lib.recursiveUpdate (mkUsers [
        # interactive
        "steve"
        "user"
        "media"
        # services
        "grafana"
        "kea"
        "nats"
        "nginx"
        "unbound"
        "vault"
      ]) {
        steve = {
          group = "users";
          extraGroups = ["wheel" "audio" "video"];
        };
      };
    users.groups = mkGroups [
      "exporters"
      "media"
      "media-group"
      # services
      "grafana"
      "kea"
      "nats"
      "nginx"
      "unbound"
      "vault"
    ];

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
      lsof
      novnc
      ripgrep
      starship
      vault-bin
      vim
      wget
      wireguard-tools
      #
      packages.hello-custom
    ];
    environment.homeBinInPath = true;

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
      enable = config.my.services.tailscale.enable;
      port = config.const.ports.tailscale.port;
      useRoutingFeatures = "both";
    };
    services.chrony = {
      enable = true;
      serverOption = "offline"; # "offline" if machine is frequently offline
      servers = config.const.ntpServers.us;
    };

    networking = {
      hostName = "aster"; # Define your hostname.
      hostId = "5e798d29"; # first 8 chars of /etc/machine-id
      wireless.enable = false;
      extraHosts = ''
        ${nginxIP} ${fqdn}
        ${nginxIP} vault.${fqdn}
        ${mediaIP} jellyfin.${fqdn}
        ${mediaIP} qbittorrent.${fqdn}
        ${mediaIP} sonarr.${fqdn}
        ${mediaIP} radarr.${fqdn}
        ${mediaIP} jackett.${fqdn}
        ${mediaIP} prowlarr.${fqdn}
        ${mediaIP} audiobookshelf.${fqdn}
      '';

      useNetworkd = true;

      firewall = with config.const.ports; {
        enable = true;
        allowedUDPPorts = [dns.port];
        allowedTCPPorts =
          [ssh.port dns.port]
          ++ (lib.optionals config.my.services.tailscale.enable [tailscale.port])
          ++ (lib.optionals config.my.containers.vault.enable [vault.apiPort vault.clusterPort]);
      };

      nftables = {
        enable = true;
        checkRuleset = true;
        tables."container-fwd" = {
          name = "container-fwd";
          enable = true;
          family = "ip";
          content = ''
            chain pre {
              type nat hook prerouting priority -100;

              # forward incoming http,https to nginx or media container
              tcp dport {80,443} dnat to ${activeHttp}
            }
            chain post {
              type nat hook postrouting priority srcnat; policy accept;

              # from trusted containers to WAN
              ip saddr 10.55.0.0/24 ip daddr != 10.55.0.0/24 masquerade

              # http,https from wan to nginx
              ip daddr ${activeHttp} masquerade
            }
          '';
        };
      };
      timeServers = config.const.ntpServers.us;
    };
    system.stateVersion = "24.05";
  };
}
