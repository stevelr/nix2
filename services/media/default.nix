# services/media/default.nix
#
# TODO: test jellyfin gpu configuration
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.myLib) mkUsers mkGroups;
  inherit (lib) concatMapStrings concatStringsSep types mkOption;
  inherit (builtins) elem;

  cfg = config.my.media;

  dataDir = s: "${cfg.storage.localBase}/data/${s}";

  mkQbittorrent = (import ./qbittorrent.nix {inherit pkgs config;}).mkQbittorrentService;
  mkJellyfin = (import ./jellyfin.nix {inherit pkgs config;}).mkJellyfinService;

  # TODO: resolver?
  #resolver             ${bridgeCfg.gateway};

  # nginx template for backend service
  serverConfig = name: ''
    server {
      listen                    80;
      server_name               ${name}.${cfg.urlDomain};
      return                    301  https://$host$request_uri;
    }
    server {
      listen                    443 ssl;
      http2                     on;
      server_name               ${name}.${cfg.urlDomain};
      location / {
        proxy_pass              http://127.0.0.1:${toString config.my.ports.${name}.port};
        proxy_set_header        Host $host;  # was $server_name
      }
    }
  '';

  # nginx template for static site that is also marked default for the listen IP address
  staticSite = host: www: ''
    server {
      listen                    80 default_server;
      server_name               ${host};
      return                    301  https://$host$request_uri;
    }
    server {
      listen                    443 ssl default_server;
      server_name               ${host};
      location / {
        autoindex off;
        root ${www};
      }
    }
  '';
in {
  options.my.media = mkOption {
    type = types.nullOr (types.submodule {
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
        backends = mkOption {
          type = types.listOf types.str;
          description = "backend services within container";
          default = [];
          example = ["jellyfin"];
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
      };
    });
    default = null;
    description = "media server config and components";
  };

  config.containers = lib.optionalAttrs cfg.enable {
    "${cfg.container}" = {
      autoStart = false; # started by wrapper config
      ephemeral = true; # wipe and restart root volumes. all persistend data is mounted
      extraFlags = ["--network-namespace-path=/run/netns/${cfg.namespace}"];
      enableTun = true;
      bindMounts = {
        "${cfg.storage.localBase}" = {
          hostPath = cfg.storage.hostBase;
          isReadOnly = false;
        };
        "/etc/ssl/nginx" = {
          hostPath = "/root/certs/aster.pasilla.net";
        };
        # gpu
        "/dev/dri/renderD128" = {
          hostPath = "/dev/dri/renderD128";
          isReadOnly = false;
        };
      };

      config = {
        environment.systemPackages = with pkgs; [
          bind.dnsutils
          jq
          lsof
          nmap
          helix
        ];
        # these didn't get set
        # environment.variables = {
        #   XDG_DATA_HOME = "${cfg.storage.localBase}/data";
        #   XDG_CONFIG_HOME = "${cfg.storage.localBase}/config";
        #   XDG_CACHE_HOME = "${cfg.storage.localBase}/cache";
        # };
        networking = {
          nftables = {
            enable = true;
          };
          firewall = {
            enable = true;
            allowedTCPPorts = [80 443];
          };
          # add each backend to /etc/hosts (within the container)
          extraHosts =
            concatStringsSep "\n"
            (map (s: "127.0.0.1 ${s} ${s}.${cfg.urlDomain}") cfg.backends);
        };

        # create users. Each backend runs as its own userid
        # and is also a member of "media-group"
        users.users = mkUsers config.my.userids ([
            "nginx"
          ]
          ++ cfg.backends);
        users.groups = mkGroups config.my.userids ([
            "media-group"
            "nginx"
          ]
          ++ cfg.backends);

        services.openssh = {
          enable = true;
        };

        services.sonarr = {
          enable = elem "sonarr" cfg.backends;
          user = "sonarr";
          group = "sonarr";
          dataDir = dataDir "sonarr";
        };

        services.radarr = {
          enable = elem "radarr" cfg.backends;
          user = "radarr";
          group = "radarr";
          dataDir = dataDir "radarr";
        };

        systemd.services.qbittorrent = mkQbittorrent cfg;
        systemd.services.jellyfin = mkJellyfin cfg;

        services.nginx = {
          enable = true;
          user = "nginx";
          group = "nginx";
          validateConfigFile = true;
          recommendedGzipSettings = true;
          recommendedOptimisation = true;
          recommendedTlsSettings = true;
          recommendedProxySettings = true;
          serverTokens = false;
          sslProtocols = "TLSv1.3";

          appendConfig = ''
            worker_processes 2;
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
            log_format myformat '$http_x_forwarded_for $remote_addr [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $upstream_response_time';
          '';

          # generate server{} stanzas for each backend
          appendHttpConfig =
            #(lib.optionalString (!isNull cfg.staticSite) (staticSite "${cfg.urlDomain}" "/etc/www"))
            # ignore staticSite param and use generated file
            (staticSite "${cfg.urlDomain}" "/etc/www")
            # backends
            + (concatStringsSep "\n" (map (s: serverConfig s) cfg.backends));
        };

        environment.etc."resolv.conf".text = let
          # set dns resolver to the vpn's dns
          # set edns0 to enable extensions including DNSSEC
          nameservers =
            concatMapStrings (ip: ''
              nameserver ${ip}
            '')
            config.my.vpnNamespaces.${cfg.namespace}.vpnDns;
        in
          lib.mkForce ''
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
              <p><a href="https://jellyfin.${cfg.urlDomain}">jellyfin</a></p>
              <p><a href="https://sonarr.${cfg.urlDomain}">sonarr</a></p>
              <p><a href="https://radarr.${cfg.urlDomain}">radarr</a></p>
              <p><a href="https://qbittorrent.${cfg.urlDomain}">qbittorrent</a></p>
            </div>
          </body>
          </html>
        '';

        services.resolved.enable = false;
        environment.variables.TZ = config.my.containerCommon.timezone;
        system.stateVersion = config.my.containerCommon.stateVersion;
      };
    };
  };
}
