#
#
# TODO: encrypted swap?
#    randomEncryption = true;
# TODO: cache partitions
#
{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (lib) listToAttrs imap1;

  hostId = config.my.hostId;
  hostName = config.my.hostName;

  # efiMountSpecAttr = drive: let
  #   drivePart = "${drive}-part${toString config.my.fs.partitions.EFI}";
  # in {
  #   mountPoint = "/boot/efis/${drivePart}";
  #   device = "/dev/disk/by-id/${drivePart}";
  #   fsType = "vfat";
  #   options = ["x-systemd.idle-timeout=1min" "x-systemd.automount" "noauto"];
  # };

  mirrorBoot = idx: drive: {
    # When using disko-install, we will overwrite this value from the commandline
    # /dev/nvme${idx}n1
    device = "/dev/disk/by-id/${drive}-${toString idx}";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        # BIOS boot partition
        MBR = {
          name = "bios${toString idx}";
          type = "EF02"; # for grub MBR
          size = config.fs.partitions.legacyBIOS.size;
          priority = 1; # Needs to be first partition
        };
        # ESP
        ESP = {
          name = "Nixos-${config.my.hostname}-drive${toString idx}";
          type = "EF00";
          size = config.fs.partitions.EFI.size;
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot/efis/${drive}-part${toString config.my.fs.partitions.EFI}";
            mountOptions = ["umask=0077" "x-systemd.idle-timeout=1min" "x-systemd.automount" "noauto"];
          };
        };
        boot = {
          name = "boot${toString idx}";
          size = config.fs.partitions.boot.size;
          alignment = 8;
          content = {
            mountpoint = "/boot";
            type = "zfs";
            pool = "zboot";
          };
        };
        zroot = {
          name = "zpool-root${toString idx}";
          size = config.fs.partitions.main.size;
          alignment = 8;
          content = {
            type = "zfs";
            pool = "zroot";
          };
        };
        swap = {
          name = "swap=${toString idx}";
          size = config.fs.partitions.swap.size;
          alignment = 8;
          content.type = "none";
        };
        # fixme: swap
        spare = {
          name = "spare=${toString idx}";
          size = config.fs.partitions.spare.size ? "100%";
          alignment = 8;
          content.type = "none";
        };
      };
    };
  };
in {
  modules = [
    inputs.disko.nixosModules.disko
    {
      disko.devices = {
        disk = listToAttrs (
          imap1 (idx: d: {
            name = "${d}";
            value = mirrorBoot idx d;
          })
          config.my.fs.mirrorDrives
        );

        # cache = {
        #   type = "disk";
        #   device = "/dev/vdc";
        #   content = {
        #     type = "gpt";
        #     partitions = {
        #       zfs = {
        #         size = "100G";
        #         content = {
        #           type = "zfs";
        #           pool = "zroot";
        #         };
        #       };
        #     };
        #   };
        # };
      };
      zpool = {
        zboot = {
          type = "zpool";
          mode = {
            topology = {
              type = "topology";
              vdev = [
                {
                  mode = "mirror";
                  members =
                    map (d: "/dev/disk/by-id/${d}_part${toString config.my.partitions.boot.id}") config.my.fs.mirrorDrives;
                }
              ];
            };
          };
          datasets = {
            "zboot-${hostId}" = {
              type = "zfs_fs";
              mountpoint = "none";
              options = {
                atime = "on";
                relatime = "on";
                mountpoint = "none";
              };
            };
            "zboot-${hostId}/${hostName}" = {
              type = "zfs-fs";
              mountpoint = "none";
              options = {
                mountpoint = "none";
              };
            };
            "zboot-${hostId}/${hostName}/boot" = {
              type = "zfs_fs";
              mountpoint = "/boot";
              options = {
                mountpoint = "/boot";
                atime = "off";
              };
            };
          };
        };
        zroot = {
          type = "zpool";
          options = {
            #encryption = "on"; #
            cachefile = ""; # "" for default location
          };
          mode = {
            topology = {
              type = "topology";
              vdev = [
                {
                  mode = "mirror";
                  members =
                    map (d: "/dev/disk/by-id/${d}_part${toString config.my.partitions.root.id}") config.my.fs.mirrorDrives;
                }
              ];
              # special = {
              #   members = ["z"];
              # };
              # cache = ["cache"];
            };
          };
          rootFsOptions = {
            compression = "none";
            acltype = "posixacl";
            xattr = "sa";
            "com.sun:auto-snapshot" = "false";
            mountpoint = "none";
          };
          datasets = let
            zrootBase = "zroot-${hostId}";
            zrootHostBase = "zroot-${hostId}/${hostName}";
          in {
            "${zrootBase}" = {
              type = "zfs_fs";
              mountpoint = "none";
              options = {
                atime = "on";
                relatime = "on";
                mountpoint = "none";
              };
            };
            "${zrootHostBase}" = {
              type = "zfs-fs";
              mountpoint = "/";
              options = {
                mountpoint = "/";
                #encryption = "aes-256-gcm";
                #keyformat = "passphrase";
                ##keylocation = "file:///tmp/secret.key";
                #keylocation = "prompt";
              };
            };
            "${zrootHostBase}/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options = {
                mountpoint = "/nix";
                atime = "off";
                devices = "off";
                #encryption = "none";
              };
            };
            "${zrootHostBase}/tmp" = {
              type = "zfs_fs";
              mountpoint = "/tmp";
              options = {
                mountpoint = "/tmp";
                sync = "disabled";
              };
            };
            "${zrootHostBase}/var/tmp" = {
              type = "zfs_fs";
              mountpoint = "/var/tmp";
              options = {
                mountpoint = "/var/tmp";
                sync = "disabled";
              };
            };
            "${zrootHostBase}/var/cache" = {
              type = "zfs_fs";
              mountpoint = "/var/cache";
              options = {
                mountpoint = "/var/cache";
              };
            };
            "${zrootHostBase}/home" = {
              type = "zfs_fs";
              mountpoint = "/home";
              options = {
                mountpoint = "/home";
                compression = "lz4";
                devices = "off";
              };
            };
            "${zrootHostBase}/var/lib" = {
              type = "zfs_fs";
              mountpoint = "/var/lib";
              options = {
                mountpoint = "/var/lib";
                acltype = "posix";
                xattr = "sa";
                devices = "off";
              };
            };
            "${zrootHostBase}/var/lib/db" = {
              type = "zfs_fs";
              mountpoint = "/var/lib/db";
              options = {
                mountpoint = "/var/lib/db";
                ashift = config.my.fs.ashift;
              };
            };
            "${zrootHostBase}/var/lib/media" = {
              type = "zfs_fs";
              mountpoint = "/var/lib/media";
              options = {
                mountpoint = "/var/lib/media";
              };
            };
            # scratch volume - not backed up
            # also not host-specific - can be mounted on other hosts
            "${zrootBase}/scratch" = {
              type = "zfs_fs";
              mountpoint = "/mnt/scratch";
              options = {
                mountpoint = "/mnt/scratch";
                sync = "disabled";
                compression = "on";
              };
            };
          };
        };
      };
      # # ?? tmpfs?
      # nodev."/" = {
      #   fstype = "tmpfs";
      #   mountOptions = [
      #     "size=2G"
      #     "defaults"
      #     "mode=755"
      #   ];
      # };
    }
  ];
}
