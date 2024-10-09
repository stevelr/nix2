# Options specific to this particular host machine.
{
  config,
  pkgs,
  lib,
  hostname,
  ...
}: let
  inherit (builtins) pathExists;
  inherit (lib.lists) optional;
  mkUsers = pkgs.myLib.mkUsers config.my.userids;
  mkGroups = pkgs.myLib.mkGroups config.my.userids;
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
in {
  imports =
    [
      ./configuration.nix
      ./zfs
      ./networking
      ./virtualisation.nix
      ../../services
      ../../modules/spell-checking.nix
      ./hardware-configuration.nix
    ]
    ++ (optional (pathExists ./private.nix) ./private.nix);

  config = {
    # my.service.fail2ban.trustedIp = {
    #   ipv4 = [ "10.135.1.214" ];   # cilantro
    # };

    my.zfs = {
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
      pools = let
        id = "jwr9us";
      in {
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

    my.pre.subnets = {
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

    my.pre.containers = {
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

    my.pre.hostNets = {
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

    my.service.tailscale.enable = true;

    my.service.kea.control-agent = {
      enable = true;
      port = config.my.ports.kea.port;
    };

    # enable all users and groups on pangea

    users.users = lib.recursiveUpdate (mkUsers []) {
      # extra user attributes
      steve = {
        extraGroups = ["wheel" "audio" "podman" "incus-admin"];
      };
      user = {
        extraGroups = ["podman" "incus"];
      };
    }; # // exporterUsers;
    users.groups = mkGroups [];

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

      # Not doing this anymore, because the latest kernel versions can cause problems due to being
      # newer than what the other packages in the stable NixOS channel expect.  E.g. it caused trying
      # to use a version of the VirtualBox extensions modules (or something) for the newer kernel but
      # this was marked broken which prevented building the NixOS system.
      #
      # # Use the latest kernel version that is compatible with the used ZFS
      # # version, instead of the default LTS one.
      # kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
      # # Following https://nixos.wiki/wiki/Linux_kernel --
      # # Note that if you deviate from the default kernel version, you should also
      # # take extra care that extra kernel modules must match the same version. The
      # # safest way to do this is to use config.boot.kernelPackages to select the
      # # correct module set:
      # extraModulePackages = with config.boot.kernelPackages; [ ];

      kernelParams = [
        #"video=HDMI-A-1:3440x1440@100"  # Use 100 Hz, like xserver.
        #"video=eDP-1:d"  # Disable internal lid screen.
        #"tuxedo_keyboard.state=0"              # backlight off
        #"tuxedo_keyboard.brightness=25"        # low, if turned on
        #"tuxedo_keyboard.color_left=0xff0000"  # red, if turned on
      ];

      zfs.requestEncryptionCredentials = false; # Or could be a list of selected datasets.

      # enable dynamically installing systemd units. Needed by extra-container
      extraSystemdUnitPaths = ["/etc/systemd-mutable/system"];

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

    time.timeZone = config.my.containerCommon.timezone;

    #console.font = "ter-v24n";

    #hardware.cpu.amd.updateMicrocode = true;

    # Enable sound.
    # 'sound' not supported after 24.05. What's the new way?
    #sound.enable = true;
    hardware.pulseaudio.enable = false;

    # Bluetooth
    #hardware.bluetooth.enable = true;
    #services.blueman.enable = true;

    # Controls for Tuxedo Computers hardware that also work on my Clevo NH55EJQ.
    #hardware.tuxedo-keyboard.enable = true;  # Also enabled by the next below.
    # I use this for dynamic fan-speed adjusting based on CPU temperature.
    #hardware.tuxedo-rs.enable = true;
    #hardware.tuxedo-rs.tailor-gui.enable = is.GUI;

    # No longer needed since NixOS 24.05 has newer kernel version, and by default it uses the
    # amd_pstate_epp CPUFreq driver with that's built-in "powersave" governor, and that has similar
    # slower latency and highest frequency as the "conservative" governor, as desired.
    #
    # # Have dynamic CPU-frequency reduction based on load, to keep temperature and fan noise down
    # # when there's light load, but still allow high frequencies (limited by the separate choice of
    # # fan-speed-management-profile's curve's efficacy at removing heat) when there's heavy load.
    # # Other choices for this are: "schedutil" or "ondemand".  I choose "conservative" because it
    # # seems to not heat-up my CPUs as easily, e.g. when watching a video, which avoids turning-on
    # # the noisy fans, but it still allows the highest frequency when under sustained heavy load
    # # which is what I care about (i.e. I don't really care about the faster latency of "ondemand"
    # # nor the somewhat-faster latency of "schedutil").  Note: maximum performance is attained with
    # # the fans' speeds at the highest, which I have a different profile for in Tuxedo-rs's Tailor
    # # that I switch between as desired.
    # powerManagement.cpuFreqGovernor = "conservative";

    #services.printing.drivers = [ pkgs.hplip ];

    #hardware.sane = {
    #  enable = true;
    #  extraBackends = [ pkgs.hplipWithPlugin ];
    #};

    documentation = {
      man.enable = true; # install man page
      man.generateCaches = false; # add index cache for 'man -k' and apropos
      dev.enable = false; # man pages targeted at developers
      nixos.enable = false; # nixos docs

      # include docs for all options in the current configuration (otherwise, just base modules)
      # This option also forces us to include descriptions for all my custom options
      nixos.includeAllModules = true;
    };

    # Have debug-info and source-code for packages where this is applied.  This is for packages that
    # normally don't provide these, and this uses my custom approach that overrides and overlays
    # packages to achieve having these.
    #my.debugging.support = {
    #  all.enable = true;
    #  sourceCode.of.prebuilt.packages = with pkgs; [
    #    # TODO: Unsure if this is the proper way to achieve this for having the Rust library source
    #    # that corresponds to binaries built by Nixpkgs' `rustc`.
    #    # Have the Rust standard library source.  Get it from this `rustc` package, because it
    #    # locates it at the same `/build/rustc-$VER-src/` path where its debug-info has it recorded
    #    # for binaries it builds, and because this seems to be the properly corresponding source.
    #    # TODO: is this true, or else where is its sysroot or whatever?
    #    (rustc.unwrapped.overrideAttrs (origAttrs: {
    #      # Only keep the `library` source directory, not the giant `src` (etc.) ones.  This greatly
    #      # reduces the size that is output to the `/nix/store`.  The `myDebugSupport_saveSrcPhase`
    #      # of `myLib.pkgWithDebuggingSupport` will run after ours and will only copy the
    #      # `$sourceRoot` as it'll see it as changed by us here.  If debugging of `rustc` itself is
    #      # ever desired, this could be removed so that its sources are also included (I think).
    #      preBuildPhases = ["myDebugSupport_rust_onlyLibraryDir"];
    #      myDebugSupport_rust_onlyLibraryDir = ''
    #        export sourceRoot+=/library
    #        pushd "$NIX_BUILD_TOP/$sourceRoot"
    #      '';
    #    }))
    #  ];
    #};

    #nix = {
    #daemonCPUSchedPolicy = "idle"; daemonIOSchedClass = "idle";  # So builds defer to my tasks.
    #};
  };
}
