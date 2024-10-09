{
  config,
  inputs,
  pkgs,
  lib,
  hostname,
  ...
}: let
  inherit (builtins) attrNames listToAttrs isNull;
  inherit (lib) mkOption mkEnableOption types;
  inherit (lib.attrsets) filterAttrs;
in let
  # Choose for the particular host machine.
  hostDomain = "pasilla.net";

  valueOr = expr: other:
    if (! isNull expr)
    then expr
    else other;

  # extract first part of ip addr  "10.11.12.13" -> "10.11.12"
  first24 = addr: builtins.head (builtins.head (builtins.tail (builtins.split "([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+" addr)));
  defaultPool = addr: let
    prefix = first24 addr;
  in "${prefix}.100-${prefix}.199";

  containerOptions = {
    enable = mkOption {
      type = types.bool;
      example = false;
      description = ''
        whether the container should be enabled
      '';
      default = true;
    };

    bridge = mkOption {
      type = types.nullOr types.str;
      example = "br0";
      default = null;
      description = ''
        host bridge network and index into subnets config
      '';
    };

    address = mkOption {
      type = types.nullOr types.str;
      example = "10.100.0.43";
      default = null;
      description = ''
        Static ip of container on subnet.
        Do not use CIDR format: prefix will be obtained from the bridge's prefixLen.
        If the bridge has dhcp enabled, address can be null to use dhcp-assigned address.
      '';
    };

    name = mkOption {
      type = types.str;
      example = "pluto";
      description = ''
        Container name. also the host name for the container
      '';
    };

    prefixLen = mkOption {
      type = types.int;
      default = 24;
      description = ''
        prefix bits in network ip range
      '';
    };

    # addressCIDR = mkOption {
    #   type = types.nullOr types.str;
    #   example = "10.10.10.82/24";
    #   default = null;
    #   description = "address in CIDR form. Defaults to <address>/<prefixLen>";
    # };

    settings = mkOption {
      type = types.attrsOf types.anything;
      description = "other settings";
      default = {};
    };

    proxyPort = mkOption {
      type = types.int;
      default = 8000;
      description = ''
        primary exposed port - proxy target from nginx
      '';
    };
  };

  # # fill in defaults from containerOptions
  # makeContainer = c: {
  #   bridge = c.bridge;
  #   address = c.address;
  #   name = c.name;
  #   prefixLen = c.prefixLen;
  #   addressCIDR =
  #     if (! isNull c.address) && (isNull c.addressCIDR)
  #     then
  #       "${c.address}/${toString c.prefixLen}"
  #     else
  #       c.addressCIDR;
  #   proxyPort = c.proxyPort;
  #   settings = c.settings;
  #   enable = c.enable;
  # };

  netOptions = {
    name = mkOption {
      type = types.str;
      example = "br0";
      description = ''
        name of host interface
      '';
    };

    localDev = mkOption {
      type = types.str;
      example = "eth0";
      default = "eth0";
      description = ''
        name of interface to the bridge
      '';
    };

    gateway = mkOption {
      type = types.nullOr types.str;
      example = "10.100.0.1";
      default = null;
      description = ''
        IP address of network gateway - for routing to WAN
      '';
    };

    net = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "10.100.0.0/24";
      description = ''
        IP address of the network in CIDR format
      '';
    };

    address = mkOption {
      type = types.nullOr types.str;
      example = "10.100.0.31";
      default = null;
      description = ''
        IP address in the network. Defaults to gateway
      '';
    };

    macAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "02:03:04:05:06:07";
      description = ''
        Mac address of local interface
      '';
    };

    prefixLen = mkOption {
      type = types.int;
      default = 24;
      example = 24;
      description = ''
        Number of bits in net prefix
      '';
    };

    dns = mkOption {
      type = types.nullOr types.str;
      example = "10.100.0.1";
      default = null;
      description = ''
        The primary dns server for this net. Defaults to gateway ip.
      '';
    };

    dnsServers = mkOption {
      type = types.nullOr (types.listOf types.str);
      example = ["10.100.0.1" "9.9.9.9"];
      default = null;
      description = ''
        DNS servers to set with dhcp. Only used if dhcp.enable is true.
        Defaults to [dns]
      '';
    };

    domain = mkOption {
      type = types.nullOr types.str;
      example = "example.com";
      default = null;
      description = ''
        dns domain. Defaults to <name>.<localDomain>
      '';
    };

    dhcp = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = ''
              true to enable dhcp for this net
            '';
          };
          pool = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              default pool for DHCP server
            '';
          };
          id = mkOption {
            type = types.int;
            default = -1;
            description = ''
              default pool for DHCP server
            '';
          };
          reservations = mkOption {
            type = types.listOf (types.submodule {
              options = {
                "hw-address" = mkOption {
                  type = types.str;
                  description = "MAC address";
                };
                "ip-address" = mkOption {
                  type = types.str;
                  description = "ip address";
                };
              };
            });
            default = [];
            description = "mapping from mac address to IP within the subnet";
          };
        };
      });
      default = {enable = false;};
      example = {
        enable = true;
        pool = "10.0.0.100-10.0.0.199";
        id = 7;
      };
      description = "dhcp server configuration";
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      description = "other settings";
      default = {};
    };
  };

  makeNet = n: let
    dns = valueOr n.dns n.gateway;
    hasDhcp = (! isNull n.dhcp) && n.dhcp.enable;
  in {
    name = n.name;
    localDev = n.localDev;
    gateway = n.gateway;
    prefixLen = n.prefixLen;
    macAddress = n.macAddress;
    address = valueOr n.address n.gateway;
    net = valueOr n.net "${first24 n.gateway}.0/${toString n.prefixLen}";
    inherit dns;
    dnsServers = valueOr n.dnsServers [dns];
    domain = valueOr n.domain "${n.name}.${config.my.localDomain}";
    settings = n.settings;
    dhcp = {
      enable = hasDhcp;
      pool =
        if hasDhcp && (! isNull n.dhcp.pool)
        then n.dhcp.pool
        else defaultPool n.gateway;
      id =
        if hasDhcp && n.dhcp.id == -1
        then (pkgs.myLib.nethash n)
        else n.dhcp.id;
      reservations =
        if hasDhcp
        then n.dhcp.reservations
        else [];
    };
  };
in {
  imports = [
    (../per-host + "/${hostname}")
    ../services
    #./debugging.nix
    ./zfs
    ./networking
    ./spell-checking.nix
    ./virtualisation.nix
  ];

  options = {
    my = {
      hostName = mkOption {
        type = types.str;
        description = "system hostname";
      };

      hostDomain = mkOption {
        type = types.str;
        description = "system domain";
      };

      localDomain = mkOption {
        type = types.str;
        example = "foo.com";
        description = "domain suffix for local internal networks. Should not be 'local' because that's reserved for mDNS";
      };

      enableIPv6 = mkOption {
        type = types.bool;
        default = true;
        description = "whether to enable IPv6 on LAN interfaces";
      };

      allowedUnfree = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "list of non-free packages to allow to be imported";
      };

      hardware.firmwareUpdates.enable = mkOption {
        type = types.bool;
        default = true;
        description = "enable irmware and microcode updates";
      };

      # allocate listening ports
      ports = mkOption {
        description = "listening ports";
        type = types.attrsOf (types.submodule {
          options = {
            port = mkOption {
              type = types.int;
              description = "listen port";
            };
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "whether the port should be opened";
            };
            description = mkOption {
              type = types.str;
              default = "";
              description = "description of port or service";
            };
          };
        });
        default = {};
      };

      userids = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            uid = mkOption {
              type = types.nullOr types.int;
              default = null;
              example = 1001;
              description = "user id";
            };
            gid = mkOption {
              type = types.nullOr types.int;
              default = null;
              example = 1001;
              description = "group id";
            };
            isInteractive = mkOption {
              type = types.bool;
              default = false;
              example = true;
              description = "true if the user logs in";
            };
          };
        });
        description = "uid and gid settings for common users";
        default = {};
      };

      # initial data to be post-processed
      pre = {
        subnets = mkOption {
          type = types.attrsOf (types.submodule {
            options = netOptions;
          });
          default = {};
          description = "bridge networks connecting containers";
        };

        containers = mkOption {
          description = "configurations for containers";
          type = types.attrsOf (types.submodule {
            options = containerOptions;
          });
          default = {};
        };

        hostNets = mkOption {
          type = types.attrsOf (types.submodule {
            options = netOptions;
          });
          default = {};
          description = "host interfaces";
        };
      };

      subnets = mkOption {
        type = types.attrsOf (types.submodule {
          options = netOptions;
        });
        default = {};
        description = "bridge networks connecting containers";
      };

      containers = mkOption {
        type = types.attrsOf (types.submodule {
          options = containerOptions;
        });
        default = {};
        description = "configurations for containers";
      };

      hostNets = mkOption {
        type = types.attrsOf (types.submodule {
          options = netOptions;
        });
        default = {};
        description = "host interfaces";
      };

      managedNets = mkOption {
        type = types.listOf (types.submodule {
          options = netOptions;
        });
        default = {};
        description = ''
          (calculated value) list of virtual bridge nets on host where will run dns and dhcp servers
        '';
      };

      containerCommon = mkOption {
        type = types.submodule {
          options = {
            stateVersion = mkOption {
              type = types.str;
              description = "default nixos stateVersion for containers";
            };
            timezone = mkOption {
              type = types.str;
              default = "Etc/UTC";
              description = "timezone for containers";
            };
          };
        };
        description = "default options for containers.";
      };

      service = mkOption {
        type = types.submodule {
          options = {
            tailscale = mkOption {
              type = types.submodule {
                options = {
                  enable = mkEnableOption "Tailscale client daemon";
                  port = mkOption {
                    type = types.port;
                    default = config.my.ports.tailscale.port;
                    description = "port to listen on for tunnel traffic";
                  };
                };
              };
              default = {enable = false;};
              description = "tailscale client daemon options";
            };

            kea = mkOption {
              type = types.submodule {
                options = {
                  control-agent = mkOption {
                    type = types.submodule {
                      options = {
                        enable = mkOption {
                          type = types.bool;
                          default = false;
                          example = true;
                          description = "enable kea control agent";
                        };
                        port = mkOption {
                          type = types.int;
                          default = config.my.ports.kea.port;
                          description = "http port for kea control agent";
                        };
                      };
                    };
                  };
                };
              };
            };
          };
        };
      };
      # files = mkOption {
      #   type = types.attrs;
      # };
    }; # options.my
  };

  config = {
    my.hostName = hostname;
    my.hostDomain = hostDomain;
    my.localDomain = "pnet";

    # I'm trying to diagnose a network problem and turning off IPv6 will help reduce debug clutter
    my.enableIPv6 = false;

    my.hardware.firmwareUpdates.enable = true;

    # defaults for containers
    my.containerCommon.stateVersion = "24.05";
    my.containerCommon.timezone = "Etc/UTC";

    # fixup missing values
    my.subnets = builtins.mapAttrs (_: n: (makeNet n)) config.my.pre.subnets;
    my.containers = builtins.mapAttrs (_: c: (makeContainer c)) config.my.pre.containers;
    my.hostNets = builtins.mapAttrs (_: n: (makeNet n)) config.my.pre.hostNets;
    # internal nets where we will run dhcp and dns servers
    my.managedNets = builtins.filter (n: n.dhcp.enable) (builtins.attrValues config.my.subnets);

    # consistent id numbering for file mounts
    my.userids = {
      # interactive users
      steve = {
        uid = 1000;
        gid = 100;
        isInteractive = true;
      };
      user = {
        uid = 1001;
        gid = 100;
        isInteractive = true;
      };

      # services
      seafile = {
        uid = 4001;
        gid = 4001;
      };
      pmail = {
        uid = 4002;
        gid = 4002;
      };
      unbound = {
        uid = 4003;
        gid = 4003;
      };
      vault = {
        uid = 4004;
        gid = 4004;
      };
      gitea = {
        uid = 4005;
        gid = 4005;
      };
      postgres = {
        uid = 4006;
        gid = 4006;
      };
      nginx = {
        uid = 4007;
        gid = 4007;
      };

      grafana = {
        uid = 4010;
        gid = 4010;
      };
      prometheus = {
        uid = 4011;
        gid = 4011;
      };
      loki = {
        uid = 4012;
        gid = 4012;
      };
      tempo = {
        uid = 4013;
        gid = 4013;
      };
      nats = {
        uid = 4014;
        gid = 4014;
      };
      clickhouse = {
        uid = 4015;
        gid = 4015;
      };
      vector = {
        uid = 4016;
        gid = 4016;
      };
      #exporter = { uid = 4017; gid = 4017; }; # generic for node exporters

      # developer group
      developer = {gid = 4500;};
      # prometheus exporters
      exporters = {gid = 4501;};
    };

    my.ports = {
      clickhouseHttp = {port = 8123;};
      clickhouseTcp = {port = 9000;};
      incus = {port = 10200;};
      kea = {port = 14461;};
      nats = {port = 4222;};
      node = {
        port = 9100;
        description = "node exporter";
      };
      ssh = {port = 22;};
      tailscale = {port = 41641;}; # config.my.service.tailscale.port;
      unbound = {port = 53;};
      vault = {
        port = 8200;
        description = "Hashicorp vault api port";
      };
      vector = {port = 8686;};
      ##qryn = { port = 3100; };
    };

    ##
    ## -----
    ##

    # set host to same UTC timezone as containeres
    time.timeZone = config.my.containerCommon.timezone;

    networking.timeServers = [
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

    boot = {
      tmp = {
        cleanOnBoot = true;
        # useTmpfs = true;
      };
      # needed for clickhouse and iotop
      kernel.sysctl."kernel.task_delayacct" = 1;
    };

    i18n.defaultLocale = "en_US.UTF-8";

    console = {
      # earlySetup = true;
      packages = with pkgs; [
        # console fonts, keymaps, other resources for console
        terminus_font
      ];
      #useXkbConfig = true; # configure virtual console keypam from x server settings
      keyMap = "us";
    };

    # For each normal user, give it its own sub-directories under /mnt/scratch/home/ and
    # /var/tmp/home/.  This is especially useful for a user to place large dispensable things that
    # it wants to be excluded from backups.
    systemd.tmpfiles.packages = let
      mkTmpfilesDirPkg = base:
        (
          pkgs.myLib.tmpfiles.mkDirPkg'
          {
            ${base} = {
              user = "root";
              group = "root";
              mode = "0755";
            };
          }
          (listToAttrs (map
            (userName: {
              name = userName;
              value = {
                user = userName;
                group = "users";
                mode = "0700";
              };
            })
            (attrNames (filterAttrs (n: v: v.isNormalUser) config.users.users))))
        )
        .pkg;
    in
      map mkTmpfilesDirPkg [
        "/var/tmp/home"
      ];

    # enable sudo and generate /etc/sudoers file
    security.sudo = {
      enable = true;
      extraRules = [
        # allow users in group wheel to run nixos-rebuild, with any args, without password
        {
          groups = ["wheel"];
          commands = with pkgs; [
            {
              command = "${nixos-rebuild}/bin/nixos-rebuild";
              options = ["SETENV" "NOPASSWD"];
            }
            {
              command = "${systemd}/bin/systemctl";
              options = ["SETENV" "NOPASSWD"];
            }
            {
              command = "ALL";
              options = ["SETENV"];
            }
          ];
        }
        # allow all users in group wheel to execute any command, requiring password
        #{
        #  groups = [ "wheel" ]; commands = [ "ALL" ];
        #}
      ];
    };

    # enable sshd
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
        X11Forwarding = true;
        X11DisplayOffset = 10;
        AcceptEnv = "OP_SERVICE_ACCOUNT_TOKEN OP_CONNECT_HOST OP_CONNECT_TOKEN";
        ChannelTimeout = "global=1h";
      };
    };

    # Some programs need SUID wrappers, can be configured further, or are
    # started in user sessions, and so should be done here and not in
    # environment.systemPackages.
    programs = {
      ssh = {
        # Have `ssh-agent` be already available for users which want to use it.  No harm in
        # starting it for users which don't use it (as long as their apps & tools are not
        # configured to accidentally use it unintentionally, but that's their choice).
        startAgent = true;
        # This is better than the other choices, because: it "grabs" the desktop (unlike GNOME's
        # Seahorse's which has some error when it tries to do that); and it doesn't depend on
        # other things (unlike KDE's ksshaskpass which depends on KWallet).
        #askPassword = mkIf is.GUI "${pkgs.ssh-askpass-fullscreen}/bin/ssh-askpass-fullscreen";
      };

      git = {
        enable = true;
        config = {
          safe.directory = let
            safeDirs = ["/etc/nixos" "/etc/nixos/users/dotfiles"];
            # Only needed because newer Git versions changed `safe.directory` handling to be more
            # strict or something.  Unsure if the consequence of now needing this was
            # unintentional of them.  If it was unintentional, I suppose it's possible that future
            # Git versions could fix to no longer need this.
            safeDirsWithExplicitGitDir =
              (map (d: d + "/.git") safeDirs)
              ++ ["/etc/nixos/.git/modules/users/dotfiles"];
          in
            safeDirs ++ safeDirsWithExplicitGitDir;
          transfer.credentialsInUrl = "die";
        };
      };

      gnupg.agent = {
        enable = true;
        enableExtraSocket = true; # Why not? Upstream's default is this. Helps forwarding.
        enableBrowserSocket = true; # Why not?
        #enableSSHSupport = true;  # Would only be for using GPG keys as SSH keys.
      };

      zsh.enable = true;
    };

    nixpkgs = {
      # overlays = with inputs.self.overlays; [
      #   helperLib
      #   unstableChannel
      # ];

      config = {
        # Allow and show all "unfree" packages that are available.
        # Need this for firmware, 1password cli, graphics drivers, etc.
        allowUnfree = true;
      };
    };

    #environment.etc."nix/path/nixpkgs".source = inputs.nixpkgs;

    environment.systemPackages = with pkgs;
      [
        # git  # Installed via above programs.git.enable
        alsa-lib
        bind.dnsutils
        clickhouse
        cobalt # static site gen
        zola # static site gen
        fd
        file
        gnupg
        helix
        hello-custom # test overlays
        htop
        hydra-check
        iotop
        jq
        just
        lsb-release
        man-pages
        man-pages-posix
        natscli
        ncurses
        openssl
        nixos-generators
        pciutils # lspci
        podman
        podman-compose
        usbutils
        psmisc
        pwgen
        qemu_full
        quickemu
        ripgrep
        rsync
        sops # simple flexible tool for secrets
        tmux
        unzip
        vim
        wget
        xorg.xauth # needed for X11Forwarding
        xorg.xeyes # for testing X connections
      ]
      ++ (import ./handy-tools.nix {inherit pkgs;}).full;

    environment.variables = rec {
      # Use absolute paths for these, in case some usage does not use PATH.
      VISUAL = "${pkgs.vim}/bin/vim";
      EDITOR = VISUAL;
      PAGER = "${pkgs.less}/bin/less";
      # Prevent Git from using SSH_ASKPASS (which NixOS always sets).  This is
      # a workaround hack, relying on unspecified Git behavior, and hopefully
      # this is only temporary until a proper resolution.
      GIT_ASKPASS = "";
    };

    environment.homeBinInPath = true;

    nix = {
      settings = {
        auto-optimise-store = true;
        experimental-features = ["nix-command" "flakes"];
      };

      nixPath = ["/etc/nix/path"];
      # This fixes nixpkgs (for e.g. "nix shell") to match the system nixpkgs
      registry.nixpkgs.flake = inputs.nixpkgs;

      gc = {
        # Note: This can result in redownloads when store items were not
        # referenced anywhere and were removed on GC, but it is convenient.
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 90d";
      };
    };

    # system.autoUpgrade.enable = true;

    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    system.stateVersion = "24.05"; # Did you read the comment?
  };
}
