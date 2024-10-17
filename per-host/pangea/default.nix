# Options specific to this particular host machine.
{ config
, pkgs
, lib
, ...
}:
let
  inherit (builtins) pathExists;
  inherit (lib) optional attrNames listToAttrs filterAttrs;
  inherit (pkgs.myLib) mkUsers;

  # exporterUsers = (listToAttrs (map
  #   (exp: {
  #     name = exp.user;
  #     value = { isSystemUser = true; group = exp.group; };
  #   })
  #   (builtins.filter
  #       (e: e.enable)
  #       (builtins.attrValues config.services.prometheus.exporters)
  #   )
  # ));
  # exporterGroups = (listToAttrs (map
  #   (exp: {
  #     name = exp.user;
  #     value = { isSystemUser = true; group = exp.group; };
  #   })
  #   (filter (v: v.enable && v.group != "exporters") (attrValues config.services.prometheus.exporters))
  # ));
in
{
  imports =
    [
      ./zfs
      ./networking
      ./virtualisation.nix
      ../../services
      ../../modules/spell-checking.nix
      ../../modules/debugging.nix
      ./hardware-configuration.nix
    ]
    ++ (optional (pathExists ./private.nix) ./private.nix);

  config = {
    my = {
      hostName = "pangea";
      hostDomain = "pasilla.net";
      localDomain = "pnet";

      zfs = {
        mirrorDrives = [
          # Names under /dev/disk/by-id/
          "nvme-CT4000T700SSD5_2407E897EE02" # nvme0n1
          "nvme-CT4000T700SSD5_2340E87BAD3F" # nvme1n1
        ];
        partitions = {
          legacyBIOS = 1;
          EFI = 2;
          boot = 3;
          main = 4;
          swap = 5;
        };
        pools =
          let
            id = "jwr9us";
          in
          {
            boot.name = "boot-${id}";
            main.name = "main-${id}";
          };
        usersZvolsForVMs = [
          {
            id = "1";
            owner = "steve";
          }
          {
            id = "2";
            owner = "steve";
          }
          #{ id = "3"; owner = "steve"; }
          #{ id = "4"; owner = "steve"; }
          # { id = "5"; owner = ; }
          # { id = "6"; owner = ; }
          # { id = "7"; owner = ; }
          # { id = "8"; owner = ; }
        ];
        encryptedHomes = {
          noAuto = [
            #"/home/v"
            #"/home/v/old"
            #{ mountPoint = "/mnt/omit/home/v"; subDataset = "/home/v/omit"; }
          ];
        };
      };

      pre.subnets = {
        # lan network upstream
        "pangea-lan0" = {
          name = "lan0";
          gateway = "10.135.1.1";
          domain = "pasilla.net";
        };

        ##
        ## Internal bridges
        ##

        "container-br0" = {
          name = "br0";
          gateway = "10.144.0.1";
          dhcp.enable = true;
          dhcp.reservations = [
            # seafile container ip address
            (with config.my.containers.seafile; {
              "hw-address" = settings.macAddr;
              "ip-address" = address;
            })
          ];
        };

        # future nets
        "appNet2" = {
          name = "appNet2";
          gateway = "10.144.2.1";
          dhcp.enable = true;
        };

        # default podman network(s)
        # Not sure what I want to do about this ...
        # should we add dns and/or dhcp server?
        "pangea-podman0" = {
          name = "podman0";
          net = "10.88.0.0/16";
          prefixLen = 16;
          gateway = "10.88.0.1";
        };
      };

      containers = {
        "empty" = {
          name = "empty";
          bridge = "container-br0";
          # address is assigned by dhcp
        };
        "empty-static" = {
          name = "empty-static";
          bridge = "container-br0";
          address = "10.144.0.222";
        };
        "nginx" = {
          name = "nginx";
          bridge = "container-br0";
          address = "10.144.0.15";
        };
        "gitea" = {
          name = "gitea";
          bridge = "container-br0";
          address = "10.144.0.16";
          proxyPort = 3000;
          # http listen port
          settings = {
            #http = 3000;
            ssh = 3022;
            hostSsh = 3022; # port host listens on that's forwarded to container ssh
          };
        };
        "vault" = {
          name = "vault";
          bridge = "container-br0";
          address = "10.144.0.17";
          proxyPort = config.my.ports.vault.port;
          settings = {
            enable = false;
            # internal port
            #apiPort = 8200;
            clusterPort = 8201;
            clusterName = "pasilla.net";
            # external api address
            apiAddr = "https://vault.pasilla.net";
            # external cluster address
            clusterAddr = "https://vault.pasilla.net:8201";
            # server log level: trace,debug,info.warn,err
            logLevel = "info"; #
            storagePath = "/var/lib/vault";
          };
        };
        "seafile" = {
          name = "seafile";
          bridge = "container-br0";
          address = "10.144.0.18";
          proxyPort = 8888;
          settings = {
            macAddr = "02:ca:fe:44:00:18";
            #proxyPort = 80;
          };
        };
        "grafana" = {
          name = "grafana";
          bridge = "container-br0";
          address = "10.144.0.19";
          proxyPort = 8080;
        };
        "nettest" = {
          name = "nettest";
          bridge = "container-br0";
          address = "10.144.0.20";
        };
        "pmail" = {
          name = "pmail";
          bridge = "container-br0";
          address = "10.144.0.21";
        };
        "clickhouse" = {
          name = "clickhouse";
          bridge = "container-br0";
          address = "10.144.0.22";
          settings = {
            httpPort = config.my.ports.clickhouseHttp.port;
            tcpPort = config.my.ports.clickhouseTcp.port;
          };
        };
        "vector" = {
          name = "vector";
          bridge = "container-br0";
          address = "10.144.0.23";
          settings = {
            apiPort = config.my.ports.vector.port;
          };
        };
      };

      pre.hostNets = {
        hostlan1 = {
          name = "hostlan1";
          localDev = "enp2s0";
          address = "10.135.1.2";
          prefixLen = 24;
          macAddress = "58:47:ca:78:38:93";
          domain = "pasilla.net";
          gateway = "10.135.1.1";
        };
        hostlan2 = {
          name = "hostlan2";
          localDev = "enp3s0";
          address = "10.135.1.36";
          prefixLen = 24;
          macAddress = "58:47:ca:78:38:92";
          domain = "pasilla.net";
          gateway = "10.135.1.1";
        };
      };

      services = {
        tailscale.enable = true;
        kea.control-agent = {
          enable = true;
          port = config.my.ports.kea.port;
        };
        unbound.enable = false;
      };

      # I'm trying to diagnose a network problem and turning off IPv6 will help reduce debug clutter
      enableIPv6 = false;

      hardware.firmwareUpdates.enable = true;
    };

    # enable all users and groups on pangea

    users.users = lib.recursiveUpdate (mkUsers config.my.userids [ "steve" "user" ]) {
      # extra user attributes
      steve = {
        group = "users";
        extraGroups = [ "wheel" "audio" "video" "podman" "incus-admin" ];
      };
      user = {
        extraGroups = [ "podman" "incus" ];
      };
    }; # // exporterUsers;
    #users.groups = mkGroups config.my.userids [];

    services.ntp = {
      enable = true;
      servers = [
        "0.us.pool.ntp.org"
        "1.us.pool.ntp.org"
        "2.us.pool.ntp.org"
        "3.us.pool.ntp.org"
      ];
    };

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
    systemd.tmpfiles.packages =
      let
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
          ).pkg;
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
          groups = [ "wheel" ];
          commands = with pkgs; [
            {
              command = "${nixos-rebuild}/bin/nixos-rebuild";
              options = [ "SETENV" "NOPASSWD" ];
            }
            {
              command = "${systemd}/bin/systemctl";
              options = [ "SETENV" "NOPASSWD" ];
            }
            {
              command = "ALL";
              options = [ "SETENV" ];
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
          safe.directory =
            let
              safeDirs = [ "/etc/nixos" "/etc/nixos/users/dotfiles" ];
              # Only needed because newer Git versions changed `safe.directory` handling to be more
              # strict or something.  Unsure if the consequence of now needing this was
              # unintentional of them.  If it was unintentional, I suppose it's possible that future
              # Git versions could fix to no longer need this.
              safeDirsWithExplicitGitDir =
                (map (d: d + "/.git") safeDirs)
                ++ [ "/etc/nixos/.git/modules/users/dotfiles" ];
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
      ++ (import ./handy-tools.nix { inherit pkgs; }).full;

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
        experimental-features = [ "nix-command" "flakes" ];
      };

      nixPath = [ "/etc/nix/path" ];

      # This fixes nixpkgs (for e.g. "nix shell") to match the system nixpkgs
      # FIXME
      #registry.nixpkgs.flake = inputs.nixpkgs;

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

    # zfs dataset where databases live. All dbs should be in subdirectories of this
    # this is configured with options for optimal use of databases (mysql or postgres)
    #my.postgresql.baseDataDir = "/var/lib/db";

    # no locale = significantly improves sort by reducing calls to iconv
    # encode UTF8
    # default text search English
    # data page checksums disabled
    #my.postgresql.initdbArgs = [ "--no-locale" "-E=UTF8" "-n" "-N" ];

    boot = {
      loader = {
        # If UEFI firmware can detect entries
        efi.canTouchEfiVariables = true;

        # # For problematic UEFI firmware
        # grub.efiInstallAsRemovable = true;
        # efi.canTouchEfiVariables = false;
      };

      zfs.requestEncryptionCredentials = false; # Or could be a list of selected datasets.

      # enable dynamically installing systemd units. Needed by extra-container
      extraSystemdUnitPaths = [ "/etc/systemd-mutable/system" ];

      # # To have classic ptrace permissions (instead of restricted, which is the new default).
      # # Setting this to 0 enables ptracing non-child processes, e.g. attaching GDB to an existing
      # # process, of a user's same UID.  The default value of 1 allows only child processes to be
      # # ptrace'd, e.g. GDB must start a process so it's a child.
      # kernel.sysctl."kernel.yama.ptrace_scope" = 0;
    };

    # security.pki.certificateFiles = [
    #   "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    # ];
    #  ++ (lib.lists.optional config.my.vault.enable /var/lib/vault/vault-cert.pem);

    # When booting into emergency or rescue targets, do not require the password
    # of the root user to start a root shell.  I am ok with the security
    # consequences, for this host.  Do not blindly copy this without
    # understanding.  Note that SYSTEMD_SULOGIN_FORCE is considered semi-unstable
    # as described in the file systemd-$VERSION/share/doc/systemd/ENVIRONMENT.md.
    systemd.services = {
      emergency.environment = {
        SYSTEMD_SULOGIN_FORCE = "1";
      };
      rescue.environment = {
        SYSTEMD_SULOGIN_FORCE = "1";
      };
    };

    time.timeZone = "Etc/UTC";

    #hardware.cpu.amd.updateMicrocode = true;

    hardware.pulseaudio.enable = false;

    documentation = {
      man.enable = true; # install man page
      man.generateCaches = false; # add index cache for 'man -k' and apropos
      dev.enable = false; # man pages targeted at developers
      nixos.enable = false; # nixos docs

      # include docs for all options in the current configuration (otherwise, just base modules)
      # This option also forces us to include descriptions for all my custom options
      nixos.includeAllModules = true;
    };
  };

}
