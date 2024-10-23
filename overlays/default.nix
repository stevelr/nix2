# This file defines overlays
{inputs, ...}: let
  pkgs = inputs.nixpkgs;
  lib = pkgs.lib;
  isStableVersion = pkgs: isNull (lib.match "pre.*" lib.trivial.versionSuffix);
in {
  nixpkgs.overlays = [
    # convention: use args self,super for inheritance; final,prev for new/old

    # library of helpers.)
    (final: _prev:
      assert ! (_prev ? myLib); {
        myLib = import ../lib {pkgs = final;};
      })

    # import packges
    (final: _prev: let
      packages = import ../pkgs {inherit (_prev) config system pkgs;};
    in {
      inherit packages;
    })

    # Make the nixos-unstable channel available as pkgs.unstable, for stable
    # versions of pkgs only.
    (final: _prev:
      if isStableVersion _prev
      then let
        _unstable = assert ! (_prev ? unstable);
        # Pass the same config so that attributes like allowUnfreePredicate
        # are propagated.
          import inputs.nixpkgs-unstable {
            # config = config // { allowUnfree = true; };
            inherit (final) config system;
          };
      in {
        unstable = _unstable;

        # # security-related
        # _1password = _unstable._1password;
        # age = _unstable.age;
        # age-plugin-yubikey = _unstable.age-plugin-yubikey;
        # curl = _unstable.curl;
        # gnupg = _unstable.gnupg;
        # gocryptfs = _unstable.gocryptfs;
        # nats-server = _unstable.nats-server;
        # natscli = _unstable.natscli;
        # nkeys = _unstable.nkeys;
        # nsc = _unstable.nsc;
        # openssh = _unstable.openssh;
        # #openssl = _unstable.openssl;
        # podman = _unstable.podman;
        # podman-compose = _unstable.podman-compose;
        # qemu_full = _unstable.qemu_full;
        # quickemu = _unstable.quickemu;
        # rclone = _unstable.rclone;
        # restic = _unstable.restic;
        # tailscale = _unstable.tailscale;
        # usbutils = _unstable.usbutils;
        # vault-bin = _unstable.vault-bin;
        # wireguard-tools = _unstable.wireguard-tools;
        # yubikey-manager = _unstable.yubikey-manager;
        # yubikey-personalization = _unstable.yubikey-personalization;

        # # media
        # aria2 = _unstable.aria2;
        # audiobookshelf = _unstable.audiobookshelf;
        # jackett = _unstable.jackett;
        # jellyfin = _unstable.jellyfin;
        # jellyfin-ffmpeg = _unstable.jellyfin-ffmpeg;
        # jellyfin-web = _unstable.jellyfin-web;
        # prowlarr = _unstable.prowlarr;
        # qbittorrent-nox = _unstable.qbittorrent-nox;
        # radarr = _unstable.radarr;
        # sonarr = _unstable.sonarr;

        # # database
        # clickhouse = _unstable.clickhouse;
        # sqlite = _unstable.sqlite;

        # # misc
        # helix = _unstable.helix;
        # inetutils = _unstable.inetutils;
        # nix-output-monitor = _unstable.nix-output-monitor;
        # nixos-generators = _unstable.nixos-generators;
        # novnc = _unstable.novnc;
        # pciutils = _unstable.pciutils;
        # speedtest-cli = _unstable.speedtest-cli;
      }
      else {})

    # additional files
    # (import more_overlays)
  ];
}
