# per-host/fake/default.nix
#
{ config, pkgs, lib, ... }:
let
  #  inherit (pkgs.myLib) mkUsers mkGroups;
  hostDomain = "pasilla.net";
  hostName = "fake";

in
{
  imports = [
    ../../services
    ../../modules/zfs
    ./hardware-configuration.nix
  ];

  config = {
    my = {
      hostName = hostName;
      hostDomain = hostDomain;
      localDomain = "pnet";

      # services = {
      #   unbound.enable = false;
      #   tailscale.enable = false;
      #   kea.enable = false;
      # };

      zfs = {

        mirrorDrives = [
          # Names under /dev/disk/by-id/
          "nvme-CT4000T700SSD5_2407E897EE02_1" # nvme0n1
          "nvme-CT4000T700SSD5_2340E87BAD3F_1" # nvme1n1
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
            id = "999999";
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
      };
    };

    fileSystems =
      let
        inherit (lib) listToAttrs match;
        inherit (config.my.zfs) mirrorDrives firstDrive partitions pools encryptedHomes usersZvolsForVMs;


        # [ss] updated regex allows second and subsequent path components to begin with . (example: /home/user/.local)
        datasetNameRegex = "(/[[:alnum:]][[:alnum:].:_-]*)(/[[:alnum:].][[:alnum:].:_-]*)*|";


        mountSpecAttr = { mountPoint, device, fsType, options }: {
          name = mountPoint;
          value = { inherit device fsType options; };
        };
        mountSpecs = makeAttr: list: listToAttrs (map makeAttr list);

        zfsMountSpecAttr = pool: { mountPoint, subDataset ? "", options ? [ ] }:
          assert match datasetNameRegex subDataset != null;
          mountSpecAttr {
            inherit mountPoint;
            device = "${pool.name}${pool.baseDataset}${subDataset}";
            fsType = "zfs";
            options = [ "zfsutil" ] ++ options;
          };
        zfsMountSpecs = pool: mountSpecs (zfsMountSpecAttr pool);

        zfsPerHostMountSpecAttr = pool: { mountPoint, subDataset ? "", options ? [ ] }:
          assert match datasetNameRegex subDataset != null;
          zfsMountSpecAttr pool {
            inherit mountPoint options;
            subDataset = "/${hostName}${subDataset}";
          };
        zfsPerHostMountSpecs = pool: mountSpecs (zfsPerHostMountSpecAttr pool);


        # stateBindMountSpecAttr = mountPoint:
        #   mountSpecAttr {
        #     inherit mountPoint;
        #     device = "/state${mountPoint}";
        #     fsType = "none";
        #     options = [ "bind" ];
        #   };
        # stateBindMountSpecs = mounts: mountSpecs stateBindMountSpecAttr mounts;

        # efiMountSpecAttr = drive:
        #   let drivePart = "${drive}-part${toString partitions.EFI}";
        #   in mountSpecAttr {
        #     mountPoint = "/boot/efis/${drivePart}";
        #     device = "/dev/disk/by-id/${drivePart}";
        #     fsType = "vfat";
        #     options = [ "x-systemd.idle-timeout=1min" "x-systemd.automount" "noauto" ];
        #   };
        # efiMountSpecs = drives: mountSpecs efiMountSpecAttr drives;

        mkMountSpec = extra @ { ... }: spec:
          let
            attrs = if lib.isAttrs spec then spec else { mountPoint = spec; subDataset = spec; };
          in
          extra // attrs;

      in
      lib.mkMerge [
        (zfsPerHostMountSpecs pools.boot [
          { mountPoint = "/boot"; }
        ])

        (zfsPerHostMountSpecs pools.main ([
          { mountPoint = "/"; }
        ] ++ (map (mkMountSpec { }) [
          "/home"
          "/nix"
          "/srv"
          "/state"
          "/tmp"
          "/usr/local"
        ])))
      ];


    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    # Bootloader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # enable ip forwarding - required for routing and for vpns
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # use systemd-networkd, rather than the legacy systemd.network
    systemd.network.enable = true;

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

    services.ntp = {
      enable = true;
      servers = [
        "0.us.pool.ntp.org"
        "1.us.pool.ntp.org"
        "2.us.pool.ntp.org"
        "3.us.pool.ntp.org"
      ];
    };

    # Enable the X11 windowing system.
    services.xserver.enable = false;

    programs.zsh.enable = true;

    # Allow unfree packages
    # nixpkgs.config.allowUnfree = true;
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

    networking = {
      hostName = config.my.hostName; # Define your hostname.
      wireless.enable = false;

      useNetworkd = true;

      firewall = {
        enable = true;
        allowedUDPPorts = [ 53 ];
        allowedTCPPorts = [ 22 53 ];
      };

      nftables = {
        enable = true;
        checkRuleset = true;
      };
    };
    system.stateVersion = "24.05";
  };
}
