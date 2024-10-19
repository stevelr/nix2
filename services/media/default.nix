# services/media/default.nix
#
# TODO
#    Qbittorrent has a nat-pmp setting in the ui. Does that mean I don't need to run the natpmp client to query the forwarded port?
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
{
  config,
  pkgs,
  #unstable ? pkgs.unstable,
  lib,
  ...
}: let
  inherit (lib) concatMapStrings concatStringsSep types mkOption;

  mkUsers = pkgs.myLib.mkUsers config.my.userids;
  mkGroups = pkgs.myLib.mkGroups config.my.userids;

  cfg = config.my.media;
  nsCfg = config.my.vpnNamespaces.${cfg.namespace};

  audiobookshelf = (import ./audiobookshelf.nix {inherit pkgs config;}).mkAudiobookshelfService cfg;
  jackett = (import ./jackett.nix {inherit pkgs config;}).mkJackettService cfg;
  jellyfin = (import ./jellyfin.nix {inherit pkgs config;}).mkJellyfinService cfg;
  prowlarr = (import ./prowlarr.nix {inherit pkgs config;}).mkProwlarrService cfg;
  qbittorrent = (import ./qbittorrent.nix {inherit pkgs config;}).mkQbittorrentService cfg;
  radarr = (import ./radarr.nix {inherit pkgs config;}).mkRadarrService cfg;
  sonarr = (import ./sonarr.nix {inherit pkgs config;}).mkSonarrService cfg;

  # nginx template for backend service
  # params:
  #   host: hostname fqdn, such as "jellyfin.myhost.org"
  #   port: integer port of backend service

  # websocket headers ("Upgrade" and "Connection") required for audiobookshelf
  # included in all backends for simplicity
  serverConfig = name: port: ''
    server {
      listen                    ${nsCfg.veNsIp4}:80;
      server_name               ${name};
      return                    301 https://$host$request_uri;
    }
    server {
      listen                    ${nsCfg.veNsIp4}:443 ssl;
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
      listen                    ${nsCfg.veNsIp4}:80 default_server;
      server_name               ${host};
      return                    301 https://$host$request_uri;
    }
    server {
      listen                    ${nsCfg.veNsIp4}:443 ssl default_server;
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
        backends = mkOption {
          type = types.listOf types.str;
          description = "backend services within container";
          default = ["jellyfin"];
        };
        mediaUserExtraConfig = mkOption {
          type = types.nullOr (types.attrsOf types.anything);
          description = "additional config for users.users.media";
          default = null;
          example = {packages = [pkgs.hello];};
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
      };
    };
    default = {};
    description = "media server config and components";
  };

  config.containers = lib.optionalAttrs cfg.enable {
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
            allowedTCPPorts = [80 443] ++ (lib.optionals (!isNull cfg.sshPort) [cfg.sshPort]);
          };
          # add each backend to /etc/hosts (within the container)
          extraHosts =
            concatStringsSep "\n"
            (map (s: "127.0.0.1 ${s}.${cfg.urlDomain}") cfg.backends);
        };

        # Create users and groups. Each backend service runs with its own unique userid.
        # All backend services share the same group "media-group", which makes it easier
        # to manage files in the shared folders
        users.users =
          lib.recursiveUpdate
          (mkUsers (cfg.backends ++ ["nginx" "media"])) {
            media = cfg.mediaUserExtraConfig;
            nginx = {extraGroups = ["media-group"];};
          };
        users.groups = mkGroups (cfg.backends
          ++ [
            "media-group"
            "media"
            "nginx"
          ]);

        systemd.services =
          {}
          // audiobookshelf.services
          // jackett.services
          // jellyfin.services
          // prowlarr.services
          // qbittorrent.services
          // radarr.services
          // sonarr.services;

        # blockPorts =
        #   concatStringsSep ","
        #   (map (bk: toString config.my.ports.${bk}.port) cfg.backends);

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
            worker_processes 4;
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
            # backends
            + (concatStringsSep "\n" (map (s: serverConfig "${s}.${cfg.urlDomain}" config.my.ports.${s}.port)
                cfg.backends));
        };

        services.openssh = lib.optionalAttrs (!isNull cfg.sshPort) {
          enable = true;
          settings.PermitRootLogin = "no";
          settings.PasswordAuthentication = false;
          listenAddresses = [
            {
              addr = "${nsCfg.veNsIp4}";
              port = cfg.sshPort;
            }
          ];
          startWhenNeeded = lib.mkForce false;
        };
        services.resolved.enable = false;

        security.sudo = cfg.sudo;

        programs.zsh.enable = true;

        environment.systemPackages = with pkgs; [
          bash
          bind.dnsutils
          jq
          lsof
          nmap
          helix
          libnatpmp # TODO: move to qbittorrent
          python3 # TODO: for testing natpmp
        ];

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

        environment.variables.TZ = config.my.containerCommon.timezone;

        system.stateVersion = "24.11"; # config.my.containerCommon.stateVersion;
      };
    };
  };
}
