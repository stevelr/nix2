{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.myLib) mkUsers mkGroups configIf vpnContainerConfig;
  inherit (lib.attrsets) recursiveUpdate;
  inherit (lib) concatStringsSep;

  namespace = "ns101";
  vpnCfg = config.my.vpnNamespaces.${namespace};
  mediaStorage = "/media";
  hostMediaStorage = "/var/lib/media";

  cname = "media"; # container name
  urlDomain = "aster.pasilla.net";

  cfg = configIf config.my.containers cname;

  dataDir = s: "${mediaStorage}/data/${s}";
  cacheDir = s: "${mediaStorage}/cache/${s}";
  logDir = s: "${mediaStorage}/logs/${s}";
  configDir = s: "${mediaStorage}/config/${s}";

  backends = ["jellyfin" "sonarr" "radarr"];

  # TODO: resolver?
  #resolver             ${bridgeCfg.gateway};

  # TODO: listen ip address: vpnCfg.veNsIp4;
  serverConfig = name: ''
    server {
      listen                    80;
      server_name               ${name} ${name}.${urlDomain};
      return                    301  https://$host$request_uri;
    }
    server {
      listen                    443 ssl;
      http2                     on;
      server_name               ${name} ${name}.${urlDomain};
      location / {
        proxy_pass              http://127.0.0.1:${toString config.my.ports.${name}.port};
        proxy_set_header        Host $server_name;  # was $host
      }
    }
  '';
in {
  containers = lib.optionalAttrs cfg.enable {
    media =
      recursiveUpdate {
        autoStart = true;
        ephemeral = true; # hopefully this works if all the data is on mounted drives  ...
        bindMounts = {
          "${mediaStorage}" = {
            hostPath = hostMediaStorage;
            isReadOnly = false;
          };
          "/etc/ssl/nginx" = {
            hostPath = "/root/certs/aster.pasilla.net";
          };
        };

        config = {
          environment.systemPackages = with pkgs; [
            bind.dnsutils
            jq
            nmap
            helix
          ];
          networking = {
            nftables.enable = true;
            firewall.enable = false;
            firewall.allowedTCPPorts = [80 443];
            extraHosts = ''
              127.0.0.1 jellyfin jellyfin.${urlDomain}
              127.0.0.1 sonarr sonarr.${urlDomain}
              127.0.0.1 radarr radarr.${urlDomain}
            '';
          };

          users.users = mkUsers config.my.userids ([
              "nginx"
            ]
            ++ backends);
          users.groups = mkGroups config.my.userids ([
              "media-group"
              "nginx"
            ]
            ++ backends);

          services.jellyfin = let
            name = "jellyfin";
          in {
            enable = true;
            user = "jellyfin";
            group = "media-group";
            cacheDir = cacheDir name;
            dataDir = dataDir name;
            logDir = logDir name;
            configDir = configDir name;
          };
          services.sonarr = let
            name = "sonarr";
          in {
            enable = true;
            user = "sonarr";
            group = "media-group";
            dataDir = dataDir name;
          };
          services.radarr = let
            name = "radarr";
          in {
            enable = true;
            user = "radarr";
            group = "media-group";
            dataDir = dataDir name;
          };

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

            appendHttpConfig = concatStringsSep "\n" [
              (serverConfig "jellyfin")
              (serverConfig "sonarr")
              (serverConfig "radarr")
            ];
          };

          services.resolved.enable = false;
          environment.variables.TZ = config.my.containerCommon.timezone;
          system.stateVersion = config.my.containerCommon.stateVersion;
        };
      }
      (lib.optionalAttrs ((!isNull cfg.namespace) && config.my.vpnNamespaces.${cfg.namespace}.enable)
        (vpnContainerConfig config.my.vpnNamespaces.${cfg.namespace}));
  };
}
