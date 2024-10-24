# per-host/fake/default.nix
# minimum configuration
#
{
  config,
  pkgs,
  lib ? pkgs.lib,
  ...
}: let
  inherit (lib) types mkOption imap1 match listToAttrs;

  hostId = "110011";
  hostName = "mintest";

  root-pool = {
    name = "zroot-${hostId}";
    baseDataset = "/${hostName}";
  };
  boot-pool = {
    name = "zboot-${hostId}";
    baseDataset = "/${hostName}";
  };

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
    mountSpecAttr {
      inherit mountPoint;
      device = "${pool.name}${pool.baseDataset}${subDataset}";
      fsType = "zfs";
      options = ["zfsutil"] ++ options;
    };
  zfsMountSpecs = pool: mountSpecs (zfsMountSpecAttr pool);

  zfsPerHostMountSpecAttr = pool: {
    mountPoint,
    subDataset ? "",
    options ? [],
  }:
  # assert match datasetNameRegex subDataset != null;
    zfsMountSpecAttr pool {
      inherit mountPoint options;
      subDataset = "/${config.my.hostName}${subDataset}";
    };
  zfsPerHostMountSpecs = pool: mountSpecs (zfsPerHostMountSpecAttr pool);
in {
  imports = [
    ../../services
    ./disco.nix
    #../../modules/zfs
    ./hardware-configuration.nix
  ];

  options.my.fs.mirrorDrives = mkOption {
    type = types.listOf types.str;
    description = "mirrored boot drives";
    example = ["nvme0n1" "nvme1n1"];
  };
  options.my.fs.partitions = mkOption {
    type = types.attrsOf types.submodule {
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
    };
  };
  options.my.fs.ashift = mkOption {
    type = types.int;
    description = "zfs ashift - sector multiplier";
    default = 9;
  };

  config = {
    my = {
      hostName = hostName;
      hostDomain = "pasilla.net";
      hostId = hostId;
      localDomain = "pnet";
      pre.subnets = {};
      #fs.mirrorDrives = ["nvme0n1" "nvme1n1"];
      # drive name that comes after /dev/disk/by-id/
      fs.mirrorDrives = ["FIXME"];
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
        main = {
          id = 4;
          size = "10G";
        };
        swap = {
          id = 5;
          size = "1G";
        };
        spare = {
          id = 6;
          size = "100%";
        };
      };
      fs.ashift = 9;
    };
    # TODO: update this to match mounted files systems
    fileSystems =
      (zfsPerHostMountSpecs boot-pool [
        {mountPoint = "/boot";}
      ])
      // (zfsPerHostMountSpecs root-pool [
        {mountPoint = "/";}
        {mountPoint = "/nix";}
        {mountPoint = "/tmp";}
        {mountPoint = "/var/tmp";}
        {mountPoint = "/home";}
        {mountPoint = "/var/lib";}
        {mountPoint = "/var/lib/db";}
        {mountPoint = "/var/lib/media";}
      ])
      // (
        zfsMountSpecs root-pool [
          {
            subDataset = "/scratch";
            mountPoint = "/mnt/scratch";
          }
        ]
      );

    nix.settings.experimental-features = ["nix-command" "flakes"];

    boot.supportedFilesystems = ["zfs"];

    # enable systemd-boot EFI boot manager
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.consoleMode = "auto"; # pick suitable mode
    # # For problematic UEFI firmware
    # boot.loader.grub.efiInstallAsRemovable = true;
    # boot.loader.efi.canTouchEfiVariables = false;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.grub = {
      enable = true;
      mirroredBoots =
        imap1
        (idx: drive: {
          devices = ["/dev/disk/by-id/${drive}"];
          efiBootloaderId = "NixOS-${config.my.hostname}-boot${toString idx}";
          efiSysMountPoint = "/boot/efis/${drive}-part${toString config.my.fs.partitions.EFI}";
          path = "/boot";
        })
        config.my.fs.mirrorDrives;

      copyKernels = true;
      efiSupport = true;
      zfsSupport = true;
      extraPrepareConfig = ''
        for D in ${toString config.my.fs.mirrorDrives}; do
          DP=$D-part${toString config.my.fs.partitions.EFI}
          E=/boot/efis/$DP
          mkdir -p $E
          mount /dev/disk/by-id/$DP $E
        done
      '';
    };
    boot.efi.efiSysMountPoint = let
      firstDrive = builtins.head config.my.fs.mirrorDrives;
    in "/boot/efis/${firstDrive}-part${toString config.my.fs.partitions.EFI.id}";
    boot.generationsDir.copyKernels = true;

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
