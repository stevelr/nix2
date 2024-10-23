# services/media/default.nix
#
# TODO: browser-in-browser (?)
# TODO (2): test jellyfin gpu configuration
# TODO (3): health check and recovery services
#       (1) health check - either as separate service or ExecStartPost
#           with systemd-notify and watchdog timer
#       (2) recovery service as in
#           https://www.redhat.com/sysadmin/systemd-automate-recovery
#
# TODO (3): log file locations
#       prefer them to be in /media/log
#       some services use XDG_CONFIG_HOME for data and logs. we could use symlinks
#         (or bind mounts, like we do for nginx) to separate them
#
# This file has minimal dependencies on config: only config.const, config.my.media.
# to help make it portable to different machines
#
# setup notes:
#  - when downloading configuration for proton vpn,
#    use wireguard/linux, and be sure to turn on NAT-PMP port forwarding
#    and you must choose a server has the left-right arrow icon which means p2p
#
args @ {
  config,
  pkgs,
  lib ? pkgs.lib,
  ...
}: let
  inherit (lib) concatMapStrings concatStringsSep attrValues attrsToList mergeAttrsList;
  inherit (lib) types mkOption optionals optionalAttrs mkForce;
  inherit (builtins) filter;

  cfg = config.my.media;

  backends =
    map (s: s.value // {name = s.name;})
    (filter (s: s.value.enable) (attrsToList cfg.services));

  backendServices = [
    (import ./audiobookshelf.nix {inherit pkgs;})
    (import ./jackett.nix {inherit pkgs;})
    (import ./jellyfin.nix {inherit pkgs;})
    (import ./prowlarr.nix {inherit pkgs;})
    (import ./qbittorrent.nix {inherit pkgs;})
    (import ./radarr.nix {inherit pkgs;})
    (import ./sonarr.nix {inherit pkgs;})
  ];

  scripts = import ./scripts.nix {inherit cfg pkgs;};

  # nginx template for backend service
  # params:
  #   host: hostname fqdn, such as "jellyfin.myhost.org"
  #   port: integer port of backend service

  # websocket headers ("Upgrade" and "Connection") required for audiobookshelf
  # included for all backends for simplicity, and in case other services support ws in the future
  serverConfig = name: port: ''
    server {
      listen                    ${cfg.vpn.veNsIp4}:80;
      server_name               ${name};
      return                    301 https://$host$request_uri;
    }
    server {
      listen                    ${cfg.vpn.veNsIp4}:443 ssl;
      http2                     on;
      server_name               ${name};
      location / {
        proxy_pass              http://127.0.0.1:${toString port};
        proxy_set_header        Host $host;
        proxy_set_header        X-Real-IP $remote_addr;
        proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto $scheme;
        proxy_set_header        Upgrade $http_upgrade;
        proxy_set_header        Connection "upgrade";
        proxy_http_version      1.1;
      }
    }
  '';

  # nginx template for static site . also default_server
  staticSite = host: www: ''
    server {
      listen                    ${cfg.vpn.veNsIp4}:80 default_server;
      server_name               ${host};
      return                    301 https://$host$request_uri;
    }
    server {
      listen                    ${cfg.vpn.veNsIp4}:443 ssl default_server;
      server_name               ${host};
      location / {
        autoindex off;
        root ${www};
      }
    }
  '';
in {
  options.my.media = mkOption {
    type = types.submodule {
      options = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            enable media container
          '';
        };
        namespace = mkOption {
          type = types.str;
          description = "network namespace";
          default = "default";
          example = "ns1";
        };
        container = mkOption {
          type = types.str;
          description = "container name";
          default = "media";
        };
        urlDomain = mkOption {
          type = types.str;
          description = "domain or subdomain for https access";
          default = "media.local";
        };
        staticSite = mkOption {
          type = types.nullOr types.str;
          description = "path to static site www-root";
          example = "/var/www/html";
          default = null;
        };
        sshPort = mkOption {
          type = types.nullOr types.int;
          description = "ssh listener port, or null to disable openssh server";
          default = null;
          example = 2222;
        };
        btListenPort = mkOption {
          type = types.nullOr types.int;
          description = "bittorrent listener port. will be opened in firewall";
          default = null;
          example = 8091;
        };

        storage = mkOption {
          type = types.submodule {
            options = {
              hostBase = mkOption {
                type = types.str;
                description = "host path";
                default = "/var/lib/media";
              };
              localBase = mkOption {
                type = types.str;
                description = "base path within container";
                default = "/media";
              };
              downloads = mkOption {
                type = types.nullOr types.str;
                description = "download path. Defaults to localBase/downloads";
                default = null;
              };
            };
          };
        };
        sudo = mkOption {
          type = types.nullOr (types.attrsOf types.anything);
          description = "sudo options";
          default = null;
        };

        timeZone = mkOption {
          type = types.str;
          description = "timezone for all media containers";
          default = "Etc/UTC";
        };

        vpn = mkOption {
          type = types.attrsOf types.anything;
          description = "one of vpnNamespaces";
          # type checking is done by namespaceOptions in services.default;
          default = {};
        };

        services = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              enable = mkOption {
                type = types.bool;
                description = "enable the service";
                default = true;
              };
              user = mkOption {
                type = types.nullOr types.str;
                description = "user name of service. defaults to service name";
                default = null;
              };
              group = mkOption {
                type = types.nullOr types.str;
                description = "group name. Defaults to user name";
                default = null;
              };
              proxyPort = mkOption {
                type = types.int;
                description = "proxy http port";
                example = 8080;
              };
              extraConfig = mkOption {
                type = types.attrsOf types.anything;
                description = "additional configuration";
                default = {};
              };
            };
          });
          description = "media backend services";
          default = {};
        };
      };
    };
    default = {};
    description = "media server config and components";
  };

  config.containers = optionalAttrs cfg.enable {
    "${cfg.container}" = {
      autoStart = false; # started by wrapper config
      ephemeral = true; # wipe and restart root volumes. all persistend data is mounted
      extraFlags = ["--network-namespace-path=/run/netns/${cfg.namespace}"];
      enableTun = true;
      bindMounts = {
        media = {
          mountPoint = "${cfg.storage.localBase}";
          hostPath = "${cfg.storage.hostBase}";
          isReadOnly = false;
        };
        certs = {
          mountPoint = "/etc/ssl/nginx";
          hostPath = "/root/certs/aster.pasilla.net";
          isReadOnly = true;
        };
        # due to systemd.service.nginx hardening (as configured by the nixpkgs nginx module),
        # /media/log/nginx appears as a read-only filesystem to the nginx service. This bind mount
        # lets us log to the mounted volume but in a permitted fs path
        nginxLogs = {
          mountPoint = "/var/log/nginx";
          hostPath = "${cfg.storage.hostBase}/log/nginx";
          isReadOnly = false;
        };
        gpu = {
          mountPoint = "/dev/dri/renderD128";
          hostPath = "/dev/dri/renderD128";
          isReadOnly = false;
        };
      };

      config = {
        networking = {
          nftables = {
            enable = true;
          };
          firewall = {
            enable = true;
            allowedTCPPorts = (with config.const.ports; [http.port https.port]) ++ (optionals (!isNull cfg.sshPort) [cfg.sshPort]);
          };
          # add each backend to /etc/hosts (within the container)
          extraHosts =
            concatStringsSep "\n"
            (map (s: "127.0.0.1 ${s.name}.${cfg.urlDomain}") backends);
        };

        # Create users and groups. Each backend service runs with its own unique userid.
        # All backend services share the same group "media-group", which makes it easier
        # to manage files in the shared folders
        users.users = let
          inherit (config.const) userids;
        in {
          nginx = {
            uid = mkForce userids.nginx.uid;
            inherit (userids.nginx) group;
            extraGroups = ["media-group"];
            isSystemUser = true;
          };
          media = {
            inherit (userids.media) uid group;
            # include "wheel" if sudo is enabled
            extraGroups = ["media-group" "wheel" "render" "video"];
            packages = [
              scripts.fixPortForward
              scripts.getExternalIP
              scripts.vpnCheck
            ];
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFilbUTPgUrnInm3Nz2U0rE5oUCzx4uFgwGJYjZwmhpN user@aster"
            ];
            isNormalUser = true;
          };
          jellyfin = {
            inherit (userids.jellyfin) uid group;
            extraGroups = ["media-group" "render" "video"];
            isSystemUser = true;
          };
          sonarr = {
            inherit (userids.sonarr) uid group extraGroups;
            isSystemUser = true;
          };
          radarr = {
            inherit (userids.radarr) uid group extraGroups;
            isSystemUser = true;
          };
          qbittorrent = {
            inherit (userids.qbittorrent) uid group extraGroups;
            isSystemUser = true;
          };
          audiobookshelf = {
            inherit (userids.audiobookshelf) uid group extraGroups;
            isSystemUser = true;
          };
          jackett = {
            inherit (userids.jackett) uid group extraGroups;
            isSystemUser = true;
          };
          prowlarr = {
            inherit (userids.prowlarr) uid group extraGroups;
            isSystemUser = true;
          };
        };

        users.groups = with config.const.userids; {
          nginx = {gid = mkForce nginx.gid;};
          media = {inherit (media) gid;};
          jellyfin = {inherit (jellyfin) gid;};
          sonarr = {inherit (sonarr) gid;};
          radarr = {inherit (radarr) gid;};
          qbittorrent = {inherit (qbittorrent) gid;};
          audiobookshelf = {inherit (audiobookshelf) gid;};
          jackett = {inherit (jackett) gid;};
          prowlarr = {inherit (prowlarr) gid;};
          media-group = {inherit (media-group) gid;};
        };

        systemd.services = mergeAttrsList (map (svc: (svc.mkService cfg).services) backendServices);

        services.nginx = {
          enable = true;
          validateConfigFile = true;
          recommendedGzipSettings = true;
          recommendedOptimisation = true;
          recommendedTlsSettings = true;
          recommendedProxySettings = true;
          serverTokens = false;
          sslProtocols = "TLSv1.3";
          clientMaxBodySize = "10g"; # allow larger post sizes

          appendConfig = ''
            worker_processes 3;
          '';

          commonHttpConfig = ''
            http2                    on;
            gzip_buffers             64 8k;   # number of buffers, size of buffer
            proxy_set_header         X-Real-IP $remote_addr;
            proxy_set_header         Upgrade $http_upgrade;
            proxy_set_header         Connection $connection_upgrade;

            ssl_session_cache         shared:MozSSL:10m;
            ssl_certificate           /etc/ssl/nginx/fullchain1.pem;
            ssl_certificate_key       /etc/ssl/nginx/privkey1.pem;
            ssl_trusted_certificate   /etc/ssl/nginx/chain1.pem;

            proxy_headers_hash_max_size 2048;
            log_format myformat       '$http_x_forwarded_for $remote_addr [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $upstream_response_time';
            access_log                 /var/log/nginx/access.log myformat;
            error_log                  /var/log/nginx/error.log warn;
          '';

          # generate server{} stanzas for each backend
          appendHttpConfig =
            #(lib.optionalString (!isNull cfg.staticSite) (staticSite "${cfg.urlDomain}" "/etc/www"))
            # ignore staticSite param and use generated file
            (staticSite "${cfg.urlDomain}" "/etc/www")
            + (concatStringsSep "\n" (map (s: serverConfig "${s.name}.${cfg.urlDomain}" s.proxyPort) backends));
        };

        services.openssh = optionalAttrs (!isNull cfg.sshPort) {
          enable = true;
          settings.PermitRootLogin = "no";
          settings.PasswordAuthentication = false;
          listenAddresses = [
            {
              addr = "${cfg.vpn.veNsIp4}";
              port = cfg.sshPort;
            }
          ];
          startWhenNeeded = mkForce false;
        };
        services.resolved.enable = false;

        security.sudo = cfg.sudo;

        programs.zsh.enable = true;

        environment.systemPackages = with pkgs; [
          bash
          bind.dnsutils
          curl
          gnused
          helix
          iproute2
          jq
          lsof
          nmap
          packages.py-natpmp
        ];

        environment.etc."resolv.conf".text = let
          # set dns resolver to the vpn's dns
          # set edns0 to enable extensions including DNSSEC
          nameservers =
            concatMapStrings (ip: ''
              nameserver ${ip}
            '')
            cfg.vpn.vpnDns;
        in
          mkForce ''
            option edns0
            ${nameservers}
          '';

        environment.etc."www/index.html".text = ''
          <!doctype html>
          <html>
          <head>
            <title>Media server</title>
            <meta charset="utf-8" />
            <meta http-equiv="Content-type" content="text/html; charset=utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <style type="text/css">
              body {
                background-color: $f0f0f2;
                margin: 0;
                padding: 0;
                font-family: -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", "Open Sans", "Helvetica Neue", Helvetica, Arial, sans-serif;
              }
              div {
                width: 600px;
                margin: 5em auto;
                padding: 2em;
                background-color: #fdfdff;
                border-radius: 0.5em;
                box-shadow: 2px 3px 7px 2px rgba(0, 0, 0, 0.02);
              }
              a:link, a:visited {
                color: #38488f;
                text-decoration: none;
              }
              @media (max-width: 700px) {
                div {
                  margin: 0 auto;
                  width: auto;
                }
              }
            </style>
          </head>
          <body>
            <div>
              <h1>Jump to ...</h1>
              <p><a href="https://audiobookshelf.${cfg.urlDomain}">audiobookshelf</a></p>
              <p><a href="https://jackett.${cfg.urlDomain}">jackett</a></p>
              <p><a href="https://jellyfin.${cfg.urlDomain}">jellyfin</a></p>
              <p><a href="https://prowlarr.${cfg.urlDomain}">prowlarr</a></p>
              <p><a href="https://qbittorrent.${cfg.urlDomain}">qbittorrent</a></p>
              <p><a href="https://radarr.${cfg.urlDomain}">radarr</a></p>
              <p><a href="https://sonarr.${cfg.urlDomain}">sonarr</a></p>
            </div>
          </body>
          </html>
        '';

        environment.variables.TZ = cfg.timeZone;

        environment.etc."script_log".text =
          concatStringsSep "\n"
          (map (s: "${s.name}=${s.outPath}/bin/${s.meta.mainProgram}") (attrValues scripts));

        system.stateVersion = "24.05";
      };
    };
  };
}
