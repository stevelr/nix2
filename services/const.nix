# services/const.nix
# constants for userids  and service ports
{pkgs, ...}: let
  inherit (pkgs.lib) mkOption types;
in {
  options.const = {
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
          group = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "nginx";
            description = "default group name";
          };
          extraGroups = mkOption {
            type = types.nullOr (types.listOf types.str);
            default = null;
            example = ["audio"];
            description = "optional list of additional groups for the user";
          };
          extraConfig = mkOption {
            type = types.nullOr (types.attrsOf types.anything);
            default = null;
            example = {packages = [pkgs.hello];};
            description = "additional user attributes";
          };
        };
      });
      description = "uid and gid settings for common users";
      default = {};
    };
    # allocate listening ports
    ports = mkOption {
      description = "listening ports";
      type = types.attrsOf types.anything;
      default = {};
    };
  };

  config.const = {
    userids = {
      ##
      ## Interactive users
      ##
      steve =
        (
          if pkgs.stdenv.isDarwin
          then {
            uid = 501;
            gid = 20;
            group = "staff";
          }
          else {
            uid = 1000;
            gid = 100;
            group = "users";
          }
        )
        // {
          isInteractive = true;
        };

      # generic user, usually low permission, for dev shells and misc containers
      user = {
        uid = 5500;
        gid = 100;
        group = "users";
        isInteractive = true;
      };

      ##
      ## Service account ids starting at 5501 ...
      ## Group ids starting at 5801 ...
      ##
      # user ids 500-999 are available according to this ...
      # https://github.com/NixOS/nixpkgs/blob/f705ee21f6a18c10cff4679142d3d0dc95415daa/nixos/modules/programs/shadow.nix#L13-L14
      # .. however some unix services (sshd,ntpd,etc.) start at 998 counting down ..
      ##
      unbound = {
        uid = 5501;
        gid = 5501;
        group = "unbound";
      };
      vault = {
        uid = 5502;
        gid = 5502;
        group = "vault";
      };
      gitea = {
        uid = 5503;
        gid = 5503;
        group = "gitea";
      };
      postgres = {
        uid = 5504;
        gid = 5504;
        group = "postgres";
      };
      mysql = {
        uid = 5505;
        gid = 5505;
        group = "mysql";
      };
      clickhouse = {
        uid = 5506;
        gid = 5506;
        group = "clickhouse";
      };
      seafile = {
        uid = 5507;
        gid = 5507;
        group = "seafile";
      };
      nginx = {
        uid = 5508;
        gid = 5508;
        group = "nginx";
      };
      grafana = {
        uid = 5509;
        gid = 5509;
        group = "grafana";
      };
      prometheus = {
        uid = 5510;
        gid = 5510;
        group = "prometheus";
        extraGroups = ["exporters"];
      };
      loki = {
        uid = 5511;
        gid = 5511;
        group = "loki";
      };
      tempo = {
        uid = 5512;
        gid = 5512;
        group = "tempo";
      };
      nats = {
        uid = 5513;
        gid = 5513;
        group = "nats";
      };
      vector = {
        uid = 5514;
        gid = 5514;
        group = "vector";
      };
      kea = {
        uid = 5515;
        gid = 5515;
        group = "kea";
      };
      pmail = {
        uid = 5516;
        gid = 5516;
        group = "pmail";
      };
      # available: 5517-5549
      # skip a few
      media = {
        uid = 5550;
        gid = 5550;
        group = "media";
        isInteractive = true;
        extraGroups = ["media-group"];
      };
      jellyfin = {
        uid = 5551;
        gid = 5551;
        group = "jellyfin";
        extraGroups = ["media-group" "render" "video"];
      };
      sonarr = {
        uid = 5552;
        gid = 5552;
        group = "sonarr";
        extraGroups = ["media-group"];
      };
      radarr = {
        uid = 5553;
        gid = 5553;
        group = "radarr";
        extraGroups = ["media-group"];
      };
      qbittorrent = {
        uid = 5554;
        gid = 5554;
        group = "qbittorrent";
        extraGroups = ["media-group"];
      };
      audiobookshelf = {
        uid = 5555;
        gid = 5555;
        group = "audiobookshelf";
        extraGroups = ["media-group"];
      };
      jackett = {
        uid = 5556;
        gid = 5556;
        group = "jackett";
        extraGroups = ["media-group"];
      };
      prowlarr = {
        uid = 5557;
        gid = 5557;
        group = "prowlarr";
        extraGroups = ["media-group"];
      };

      ##
      ## Groups, starting at 5801
      ##
      # developer group
      developer = {gid = 5801;};
      # prometheus exporters
      exporters = {gid = 5802;};
      media-group = {gid = 5803;};
    };

    ##
    ## service ports
    ##
    ports = {
      # common
      ssh.port = 22;
      http.port = 80;
      https.port = 443;
      dns.port = 53;

      # services
      clickhouse = {
        http = 8123; # http protocol
        binary = 9000; # binary protocol (TCP)
      };
      incus = {port = 10200;};
      kea = {port = 14461;};
      nats = {port = 4222;};
      node-exporter = {port = 9100;};
      tailscale = {port = 41641;}; # config.my.services.tailscale.port;
      unbound = {port = 53;};
      vault = {
        apiPort = 8200;
        clusterPort = 8201;
      };
      vector = {port = 8686;};

      # media-group
      jellyfin = {port = 8096;};
      radarr = {port = 7878;};
      sonarr = {port = 8989;};
      prowlarr = {port = 9696;};
      #readarr = {port = 8787;};
      lidarr = {port = 8686;};
      bazarr = {port = 6767;};
      jackett = {port = 9117;};
      qbittorrent = {port = 11001;};
      audiobookshelf = {port = 7008;};
    };
  };
}
