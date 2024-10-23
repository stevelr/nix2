# per-host/fake/default.nix
# minimum configuration
#
{
  config,
  pkgs,
  lib ? pkgs.lib,
  inputs,
  ...
}: let
  inherit (lib) types mkOption imap1 listToAttrs mkMerge match mkForce;

  hostId = "8a6d1a7a";
  hostName = "mintest";

  boot-pool = {
    name = "zboot-${hostId}";
    baseDataset = "";
  };
  root-pool = {
    name = "zroot-${hostId}";
    baseDataset = "";
  };

  # ZFS pool names have a short alpha-numeric unique ID suffix, like: main-1z9h4t
  poolNameRegex = "([[:alpha:]]+)-([[:alnum:]]{6})";
  # ZFS dataset names as used by my options must begin with "/" and not end
  # with "/" (and meet the usual ZFS naming requirements), or be the empty
  # string.
  #datasetNameRegex = "(/[[:alnum:]][[:alnum:].:_-]*)+|";
  # [ss] updated regex allows second and subsequent path components to begin with . (example: /home/user/.local)
  datasetNameRegex = "(/[[:alnum:]][[:alnum:].:_-]*)(/[[:alnum:].][[:alnum:].:_-]*)*|";

  mountSpecAttr = {
    mountPoint,
    device,
    fsType,
    options,
  }: {
    name = mountPoint;
    value = {inherit device fsType options;};
  };
  mountSpecs = makeAttr: list: listToAttrs (map makeAttr list);

  zfsMountSpecAttr = pool: {
    mountPoint,
    subDataset ? "",
    options ? [],
  }:
    assert match datasetNameRegex subDataset != null;
      mountSpecAttr {
        inherit mountPoint;
        device = mkForce "${pool.name}${pool.baseDataset}${subDataset}";
        fsType = "zfs";
        options = ["zfsutil"] ++ options;
      };
  zfsMountSpecs = pool: mountSpecs (zfsMountSpecAttr pool);

  zfsPerHostMountSpecAttr = pool: {
    mountPoint,
    subDataset ? "",
    options ? [],
  }:
    assert match datasetNameRegex subDataset != null;
      zfsMountSpecAttr pool {
        inherit mountPoint options;
        subDataset = "/${config.my.hostName}${subDataset}";
      };
  zfsPerHostMountSpecs = pool: mountSpecs (zfsPerHostMountSpecAttr pool);

  efiMountSpecAttr = drive: let
    drivePart = "${drive}-part${toString config.my.fs.partitions.EFI.id}";
  in
    mountSpecAttr {
      mountPoint = "/boot/efis/${drivePart}";
      device = "/dev/disk/by-id/${drivePart}";
      fsType = "vfat";
      options = ["x-systemd.idle-timeout=1min" "x-systemd.automount" "noauto"];
    };
  efiMountSpecs = drives: mountSpecs efiMountSpecAttr drives;
in {
  imports = [
    ../../services
    inputs.disko.nixosModules.disko
    ./disko-config.nix
    #../../modules/zfs
    ./hardware-configuration.nix
  ];

  options.my.fs.mirrorDrives = mkOption {
    type = types.listOf types.str;
    description = "mirrored boot drives";
    example = ["nvme0n1" "nvme1n1"];
  };
  options.my.fs.partitions = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        id = mkOption {
          type = types.int;
          description = "partition number";
          example = 2;
        };
        size = mkOption {
          type = types.str;
          description = "partition size";
          example = "2g";
        };
      };
    });
  };
  options.my.fs.ashift = mkOption {
    type = types.int;
    description = "zfs ashift - sector multiplier";
    default = 9;
  };

  config = let
    mirrorDrives = config.my.fs.mirrorDrives;
    grubMB = map (x: x.devices) config.boot.loader.grub.mirroredBoots;
    lenGMB = builtins.length grubMB;
    declaredMB = map (d: ["/dev/disk/by-id/${d}"]) mirrorDrives;
    lenDMB = builtins.length declaredMB;
  in {
    assertions = [
      {
        assertion =
          (map (x: x.devices) config.boot.loader.grub.mirroredBoots)
          == (map (d: ["/dev/disk/by-id/${d}"]) mirrorDrives);
        message =
          "boot.loader.grub.mirroredBoots (count=${toString lenGMB}) ${toString grubMB} does not correspond"
          + " to only my.zfs.mirrorDrives (count=${toString lenDMB}) ${toString declaredMB}";
      }
      {
        assertion = config.boot.loader.grub.mirroredBoots != [] -> config.boot.loader.grub.devices == [];
        message = "Should not define both boot.loader.grub.devices and boot.loader.grub.mirroredBoots";
      }
    ];

    my = {
      hostName = hostName;
      hostDomain = "pasilla.net";
      hostId = hostId;
      localDomain = "pnet";
      pre.subnets = {};
      #fs.mirrorDrives = ["nvme0n1" "nvme1n1"];
      # drive name that comes after /dev/disk/by-id/
      fs.mirrorDrives = ["sdx98" "sdx99"];
      fs.partitions = {
        legacyBIOS = {
          id = 1;
          size = "1M";
        }; #mbr
        EFI = {
          id = 2;
          size = "1G";
        }; # ESP
        boot = {
          id = 3;
          size = "1G";
        };
        root = {
          id = 4;
          size = "10G"; # smaller than usual, but ok for testing
        };
        swap = {
          id = 5;
          size = "1G"; # unreasonably small, but ok for testing
        };
        spare = {
          id = 6;
          size = "100%";
        };
      };
      fs.ashift = 9;
    };

    fileSystems = mkMerge [
      (zfsPerHostMountSpecs boot-pool [
        {mountPoint = "/boot";}
      ])
      (zfsPerHostMountSpecs root-pool [
        {mountPoint = "/";}
        {mountPoint = "/nix";}
        {mountPoint = "/tmp";}
        {mountPoint = "/var/tmp";}
        {mountPoint = "/home";}
        {mountPoint = "/var/lib";}
        {mountPoint = "/var/lib/db";}
        {mountPoint = "/var/lib/media";}
      ])
      (
        zfsMountSpecs root-pool [
          {
            subDataset = "/scratch";
            mountPoint = "/mnt/scratch";
          }
        ]
      )
      (efiMountSpecs mirrorDrives)
    ];

    nix.settings.experimental-features = ["nix-command" "flakes"];

    boot.supportedFilesystems = ["zfs"];

    boot.loader = {
      systemd-boot.enable = true;
      systemd-boot.consoleMode = "auto"; # pick suitable mode
      # # For problematic UEFI firmware
      # boot.loader.grub.efiInstallAsRemovable = true;
      # boot.loader.efi.canTouchEfiVariables = false;
      efi.canTouchEfiVariables = true;
      efi.efiSysMountPoint = let
        firstDrive = builtins.head mirrorDrives;
      in "/boot/efis/${firstDrive}-part${toString config.my.fs.partitions.EFI.id}";
      generationsDir.copyKernels = true;

      grub = {
        enable = true;
        mirroredBoots =
          imap1
          (idx: drive: {
            devices = ["/dev/disk/by-id/${drive}"];
            efiBootloaderId = "NixOS-${config.my.hostName}-boot${toString idx}";
            efiSysMountPoint = "/boot/efis/${drive}-part${toString config.my.fs.partitions.EFI.id}";
            path = "/boot";
          })
          mirrorDrives;
        copyKernels = true;
        efiSupport = true;
        zfsSupport = true;
        extraPrepareConfig = ''
          for D in ${toString mirrorDrives}; do
            DP=$D-part${toString config.my.fs.partitions.EFI.id}
            E=/boot/efis/$DP
            mkdir -p $E
            mount /dev/disk/by-id/$DP $E
          done
        '';
      };
    };

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

    # List packages to be installed in system profile. To search, run:
    # $ nix search wget
    # no need to include packages in modules/common.nix
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

    # cache info
    #environment.etc."zfs/zpool.cache".source = "/state/etc/zfs/zpool.cache";

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
      hostId = hostId;
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
      timeServers = config.const.ntpServers.global;
    };
    system.stateVersion = "24.05";
  };
}
