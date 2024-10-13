# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) optionalString;

  mkUsers = pkgs.myLib.mkUsers config.my.userids;
  mkGroups = pkgs.myLib.mkGroups config.my.userids;
  nginxIP = "10.55.0.15";
  #containerNet = "10.55.0.0/24";
in {
  imports = [
    # Include the results of the hardware scan.
    ../../services
    ./hardware-configuration.nix
  ];

  config = {
    my = {
      hostName = "aster";
      hostDomain = "pasilla.net";
      localDomain = "pnet";

      # later converted to my.subnets
      pre.subnets = {
        # enp0s1
        "aster-lan0" = {
          name = "lan0";
          domain = "pasilla.net";
          gateway = "10.135.1.1";
        };

        # internal bridges
        "container-br0" = {
          name = "br0";
          gateway = "10.55.0.1";
          domain = "aster.pasilla.net";
          dhcp.enable = true;
        };
      };

      services = {
        unbound = {
          enable = true;
          wanNet = "aster-lan0";
        };
        tailscale.enable = false;
        kea.enable = false;
      };

      vpnNamespaces = {
        ns101 = {
          name = "ns101";
          enable = true;
          lanIface = "eth0";
          veNsIp4 = "192.168.10.11";
          veHostIp4 = "192.168.10.10";
          wgIp4 = "10.2.0.2"; # local (vpn client) interface addr in wg tunnel
          vpnDns = ["10.2.0.1"]; # dns server(s) for vpn clients
        };
      };

      containers = {
        nginx = let
          subdomain = "aster.pasilla.net";
        in {
          enable = true;
          name = "nginx";
          bridge = "container-br0";
          address = nginxIP;
          settings = {
            subdomain = subdomain;

            # list of containers that we proxy
            # don't include vault if we want vault to terminate tls
            backends = [];

            # [ss] is this used?
            # www = {
            #   enable = false;
            # };

            # [ss] what is this ssl section for?
            # ssl = {
            #   enable = false;
            #   hostPath = "";
            #   localPath = "";
            # };

            # bindmounts for certificates
            mounts = let
              # on aster, we have wildcard cert for all virtual hosts,
              # i.e., aster.pasilla.net and *.aster.pasilla.net
              wildcardCertPath = {hostPath = "/root/certs/${subdomain}";};
            in {
              "/var/local/www" = {hostPath = "/var/lib/www/${subdomain}";};
              "/etc/ssl/nginx/${subdomain}" = wildcardCertPath;
            };
          };
        };

        nettest = {
          enable = true;
          name = "nettest";
          bridge = "container-br0";
          address = "10.55.0.20";
          namespace = "ns101"; # make it run inside this vpn namespace
        };

        gitea = {
          enable = false;
          name = "gitea";
          bridge = "container-br0";
          address = "10.55.0.16";
          proxyPort = 3000;
          settings = {
            ssh = 3022;
            hostSsh = 3022;
          };
        };

        vault = {
          enable = true;
          name = "vault";
          bridge = "container-br0";
          address = "10.55.0.17";
          proxyPort = config.my.ports.vault.port;
          settings = {
            enable = true;
            apiPort = config.my.ports.vault.port;
            uiEnable = true;
            tls = {
              enable = true;
              chain = "/root/certs/vault.aster.pasilla.net/fullchain1.pem";
              privkey = "/root/certs/vault.aster.pasilla.net/privkey1.pem";
            };
            clusterPort = 8201;
            clusterName = "aster.pasilla.net";
            # external api address
            apiAddr = "https://vault.aster.pasilla.net:8200";
            # external cluster address
            clusterAddr = "vault.aster.pasilla.net:8201";
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
      vault-bin
      vim
      wget
      wireguard-tools
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
      enable = false;
      port = 41641;
      useRoutingFeatures = "both";
    };

    networking = {
      hostName = "aster"; # Define your hostname.
      wireless.enable = false;
      extraHosts = ''
        ${nginxIP} aster.pasilla.net
        ${nginxIP} vault.aster.pasilla.net
      '';

      useNetworkd = true;
      #networkmanager.enable = false;

      firewall = {
        enable = true;
        allowedUDPPorts = [53];
        allowedTCPPorts =
          [22 53]
          ++ (lib.optionals config.my.services.tailscale.enable [config.my.ports.tailscale.port])
          ++ (lib.optionals config.my.containers.vault.enable [config.my.ports.vault.port config.my.ports.vaultCluster.port]);
      };
      nftables = {
        enable = true;
        checkRuleset = true;
        # tables.host = {
        #   name = "host";
        #   family = "inet";
        #   content = ''
        #     chain input {
        #       # priority -20 to run before default input chain at priority 0 ("filter")
        #       type filter hook input priority -20; policy drop;
        #       iif "lo" accept
        #       ct state invalid drop
        #       ct state { established, related } counter packets 0 bytes 0 accept

        #       # any forwardPorts defined in nspawn containers are forwarded by dnat rules
        #       # in tables (ip io.systemd.nat) and (ip6 io.systemd.nat) created by systemd.
        #       # Those ports need to be accepted here at priority 0.
        #       tcp dport { ssh, http, https, \
        #           ${toString config.my.ports.nats.port}, \
        #           ${toString config.my.ports.vault.port}, \
        #           ${toString config.my.ports.vaultCluster.port}, \
        #           } accept

        #       # tailscale, if enabled
        #       ${optionalString config.my.services.tailscale.enable "udp dport ${toString config.my.ports.tailscale.port}"}

        #       # allow dhcp and icmp
        #       udp dport { 67,68 }                    accept comment "dhcp"
        #       ip protocol 1                          accept comment "icmp"
        #       meta l4proto 58                        accept comment "icmpv6"

        #       # everything else dropped
        #     }
        #   '';
        # };

        tables."container-fwd" = {
          name = "container-fwd";
          enable = true;
          family = "ip";
          content = ''
            chain pre {
              type nat hook prerouting priority -100;
              # forward incoming http,https to nginx
              tcp dport {80,443} dnat to ${nginxIP}
            }
            chain post {
              type nat hook postrouting priority srcnat; policy accept;
              # from containers to WAN
              ip saddr 10.55.0.0/24 ip daddr != 10.55.0.0/24 masquerade
              # http,https from wan to nginx
              ip daddr ${nginxIP} masquerade
            }
          '';
        };
      };

      timeServers = [
        # using ip adddresses because for kea option-data.ntp-servers needs ip addresses.
        # TODO: figure out how to make it dynamic - perhaps at container boot time?
        "23.186.168.1"
        "72.14.183.39"
        "23.150.41.123"
        "23.150.40.242"
        "162.159.200.1"
        #"0.us.pool.ntp.org"
        #"1.us.pool.ntp.org"
        #"2.us.pool.ntp.org"
        #"3.us.pool.ntp.org"
      ];
    };

    system.stateVersion = "24.11";
  };
}
