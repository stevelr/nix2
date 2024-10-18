# Created by following:
# https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/Root%20on%20ZFS.html
#
{
  config,
  pkgs,
  lib ? pkgs.lib,
  ...
}: let
  inherit
    (builtins)
    all
    attrNames
    attrValues
    catAttrs
    concatStringsSep
    elem
    elemAt
    isAttrs
    length
    listToAttrs
    match
    pathExists
    ;
  inherit (lib) mkMerge mkOption types;
  inherit (lib.lists) imap1 unique;
  inherit (lib.attrsets) filterAttrs;
in let
  allUnique = list: list == unique list;

  driveExists = id: pathExists "/dev/disk/by-id/${id}";

  # My ZFS pool names have a short alpha-numeric unique ID suffix, like: main-1z9h4t
  poolNameRegex = "([[:alpha:]]+)-([[:alnum:]]{6})";

  # ZFS dataset names as used by my options must begin with "/" and not end
  # with "/" (and meet the usual ZFS naming requirements), or be the empty
  # string.
  #datasetNameRegex = "(/[[:alnum:]][[:alnum:].:_-]*)+|";
  # [ss] updated regex allows second and subsequent path components to begin with . (example: /home/user/.local)
  datasetNameRegex = "(/[[:alnum:]][[:alnum:].:_-]*)(/[[:alnum:].][[:alnum:].:_-]*)*|";
in {
  options.my.zfs = with types; let
    driveID = (addCheck str driveExists) // {description = "drive ID";};
    #driveID = (addCheck str driveExists);
    #driveID = types.str;

    # this test fails
    #   chaned driveID to 'str', and still fails; therefore drivcID not a problem
    #   try nonEmpty: replace nonEmptyListOf with listOf: fails, nonEmpty not an issue
    #   unique?
    nonEmptyListOfUniqueDriveIDs = let
      type =
        addCheck (nonEmptyListOf driveID)
        # Must check driveExists ourself, because listOf.check does
        # not check its elemType.check.
        (l: (allUnique l) && (all driveExists l));
      #(l: (allUnique l));   # fails with is not driveID
      #(l: (all driveExists l)); # fails with error
    in
      type // {description = "${type.description} that are unique";};
    oneOfMirrorDrives = let
      type = addCheck driveID (x: elem x config.my.zfs.mirrorDrives);
    in
      type // {description = "${type.description} member of mirrorDrives";};

    partitionNum =
      ints.positive // {description = "drive partition number";};

    partitionOption = isRequired:
      mkOption (
        if isRequired
        then {
          type = uniq partitionNum;
          description = "unique partition number";
        }
        else {
          type = uniq (nullOr partitionNum);
          default = null;
          description = "unique partition number";
        }
      );

    poolOptions = {
      name = mkOption {
        type = uniq (strMatching poolNameRegex);
        description = "pool name";
      };
      baseDataset = mkOption {
        type = uniq (strMatching datasetNameRegex);
        default = "";
        description = "TODO";
      };
    };

    zvolVMsBlkDevID = (addCheck str zvolVMsBlkDevExists) // {description = "zvol VMs blkdev ID";};

    userName = (addCheck str userExists) // {description = "user name";};
  in {
    mirrorDrives = mkOption {
      type = uniq nonEmptyListOfUniqueDriveIDs;
      description = "drives to be mirrored";
    };
    firstDrive = mkOption {
      type = uniq oneOfMirrorDrives;
      default = elemAt config.my.zfs.mirrorDrives 0;
      description = "TODO: what does this do?";
    };
    partitions = {
      legacyBIOS = partitionOption false;
      EFI = partitionOption true;
      boot = partitionOption true;
      main = partitionOption true;
      swap = partitionOption false;
    };
    pools = {
      boot = poolOptions;
      main = poolOptions;
    };
    usersZvolsForVMs = mkOption {
      type = listOf (submodule {
        options = {
          id = mkOption {
            type = zvolVMsBlkDevID;
            description = "zvol unique id";
          };
          owner = mkOption {
            type = userName;
            description = "owner name";
          };
        };
      });
      default = [];
      description = "TODO";
    };
  };

  config = let
    inherit (config.my.zfs) mirrorDrives partitions firstDrive;
  in {
    # To avoid infinite recursion, must check these aspects here.
    assertions = let
      assertMyZfs = pred: message: {
        assertion = pred config.my.zfs;
        inherit message;
      };

      # Only the boot and main partitions are allowed to be the same, but the
      # others must all be unique.
      uniquePartitions = {partitions, ...}: let
        p = filterAttrs (n: v: v != null) partitions;
        distinctPartitionsNums = attrValues (
          if p.boot == p.main
          then removeAttrs p ["boot"]
          else p
        );
      in
        allUnique distinctPartitionsNums;
    in [
      (assertMyZfs uniquePartitions
        "my.zfs.partitions must be unique, except for boot and main")
      {
        assertion =
          (map (x: x.devices) config.boot.loader.grub.mirroredBoots)
          == (map (d: ["/dev/disk/by-id/${d}"]) mirrorDrives);
        message = "boot.loader.grub.mirroredBoots does not correspond to only my.zfs.mirrorDrives";
      }
      {
        assertion = config.boot.loader.grub.mirroredBoots != [] -> config.boot.loader.grub.devices == [];
        message = "Should not define both boot.loader.grub.devices and boot.loader.grub.mirroredBoots";
      }
    ];

    boot = {
      supportedFilesystems = ["zfs"];
      zfs.devNodes = "/dev/disk/by-id";

      loader = {
        grub = {
          enable = true;
          version = 20.0;
          copyKernels = true;
          efiSupport = true;
          zfsSupport = true;
          # For systemd-autofs. Designed to not use /etc/fstab (which is no
          # longer valid during drive-replacement recovery).
          extraPrepareConfig = ''
            for D in ${toString mirrorDrives}; do
              DP=$D-part${toString partitions.EFI}
              E=/boot/efis/$DP
              mkdir -p $E
              mount /dev/disk/by-id/$DP $E
            done
          '';
          mirroredBoots =
            imap1
            (i: drive: {
              devices = ["/dev/disk/by-id/${drive}"];
              efiBootloaderId = "NixOS-${config.my.hostName}-drive${toString i}";
              efiSysMountPoint = "/boot/efis/${drive}-part${toString partitions.EFI}";
              path = "/boot";
            })
            mirrorDrives;
        };

        efi.efiSysMountPoint = "/boot/efis/${firstDrive}-part${toString partitions.EFI}";

        generationsDir.copyKernels = true;
      };

      # ZFS does not support hibernation and so it must not be done.  (But suspend
      # is safe and allowed.)
      # https://nixos.wiki/wiki/ZFS
      # https://github.com/openzfs/zfs/issues/260
      kernelParams = ["nohibernate"];
    };

    services.zfs = {
      trim.enable = true;
      autoScrub.enable = true;
    };

    systemd.services.zfs-mount.enable = false;
  };
}
