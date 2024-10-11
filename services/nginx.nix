# nginx.nix
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (builtins) concatStringsSep getAttr;
  inherit (pkgs) myLib;
  inherit (config.my.containers) nginx; # gitea vault seafile;

  cfg = myLib.configIf config.my.containers "nginx";
  bridgeCfg = config.my.subnets.${nginx.bridge};
  mkUsers = myLib.mkUsers config.my.userids;
  mkGroups = myLib.mkGroups config.my.userids;
  # true if the container is proxied
  isProxied = n: lib.lists.elem n cfg.settings.backends;
in {
  containers = lib.optionalAttrs cfg.enable {
    nginx = {
      autoStart = true;
      privateNetwork = true;
      hostBridge = bridgeCfg.name;
      localAddress = "${nginx.address}/${toString bridgeCfg.prefixLen}";

      forwardPorts = builtins.map (port: {
        hostPort = port;
        containerPort = port;
      }) [80 443];

      bindMounts = cfg.settings.mounts;

      config = {
        environment.systemPackages = with pkgs; [
          bind.dnsutils # dig
          curl
          helix
          iproute2
          lsof # for debugging
          vim
        ];

        networking =
          myLib.netDefaults nginx bridgeCfg
          // {
            firewall.allowedTCPPorts = [80 443];
          };

        users.users = mkUsers ["nginx"];
        users.groups = mkGroups ["nginx"];

        services.nginx = let
          perServerConfig =
            {}
            // (lib.optionalAttrs (isProxied "gitea") {
              gitea = ''
                client_max_body_size 24m;
              '';
            })
            // (lib.optionalAttrs (isProxied "vault") {
              vault = ''
                client_max_body_size 1m;
              '';
            })
            # still debugging csrf error. might be useful info here
            # on seahub image, edit /opt/seafile/seafile-server-latest/seahub/seahub/settings.py
            #   add this line:
            # CSRF_TRUSTED_ORIGINS = ['https://seafile.pasilla.net', 'http://127.0.0.1']
            #
            # Apparently this line is also supposed to be a setting but it works without:
            # SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
            # then restart seahub container
            # reference:
            # https://stackoverflow.com/questions/70285834/forbidden-403-csrf-verification-failed-request-aborted-reason-given-for-fail
            // (lib.optionalAttrs (isProxied "seafile") {
              seafile = ''
                client_max_body_size 0;
                proxy_read_timeout   1200s;     # more time for uploads
                proxy_set_header      X-Forwarded-Proto https;

                #proxy_set_header     X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header     X-Forwarded-Host $server_name;

                access_log           /var/log/nginx/seahub.access.log seafileformat;
                error_log            /var/log/nginx/seahub.error.log;
              '';
            });

          # allow larger requests for seafile
          serverStanza = serverCfg: let
            serverName = "${serverCfg.name}.${cfg.settings.subdomain}";
          in ''
            server {
              listen                    80;
              server_name               ${serverName};
              return                    301  https://$host$request_uri;
            }
            server {
              listen                    443 ssl;
              http2                     on;
              server_name               ${serverName};
              ssl_certificate           /etc/ssl/nginx/${serverName}/fullchain1.pem;
              ssl_certificate_key       /etc/ssl/nginx/${serverName}/privkey1.pem;
              ssl_trusted_certificate   /etc/ssl/nginx/${serverName}/chain1.pem;
              ssl_protocols             TLSv1.2 TLSv1.3;
              ssl_session_timeout       10m;
              ssl_session_tickets       off;
              ssl_prefer_server_ciphers on;
              #ssl_ecdh_curve            X25519:prime256v1:secp384r1:secp521r1;
              ${perServerConfig.${serverCfg.name}}
              location / {
                proxy_pass              http://${serverCfg.address}:${toString serverCfg.proxyPort};
                proxy_set_header        Host $server_name;   # was $host
                # see if this helps: rewrite http redirects from backend server to https
                # proxy_redirect        http:// https://;
              }
            }
          '';
        in {
          enable = true;
          user = "nginx";
          group = "nginx";
          statusPage = true; # enable status page on 127.0.0.1/nginx_status and on virtual hosts
          validateConfigFile = true;
          recommendedGzipSettings = true;
          recommendedOptimisation = true;
          recommendedTlsSettings = true;
          recommendedProxySettings = true;
          serverTokens = false;
          #logError = "error_log:info";

          appendConfig = ''
            worker_processes     2;
          '';

          commonHttpConfig = ''
            gzip_buffers         64 8k;   # number of buffers, size of buffer
            proxy_set_header     X-Real-IP $remote_addr;
            proxy_set_header     Upgrade $http_upgrade;
            proxy_set_header     Connection $connection_upgrade;
            resolver             ${bridgeCfg.gateway};
            ssl_session_cache    shared:MozSSL:10m;
            proxy_headers_hash_max_size 2048;
            log_format seafileformat '$http_x_forwarded_for $remote_addr [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $upstream_response_time';
          '';

          virtualHosts."${config.my.hostName}.${config.my.hostDomain}" = let
            domain = "${config.my.hostName}.${config.my.hostDomain}";
          in
            {
              default = true;
              addSSL = true;
              http2 = true;
              serverAliases = [
                config.my.hostName
                config.my.hostDomain
              ];
              sslCertificate = "/etc/ssl/nginx/${domain}/fullchain1.pem";
              sslCertificateKey = "/etc/ssl/nginx/${domain}/privkey1.pem";
              sslTrustedCertificate = "/etc/ssl/nginx/${domain}/chain1.pem";
              locations."/._status" = {
                extraConfig = ''
                  stub_status on;
                  allow 0.0.0.0;
                '';
              };

              # static site
              locations."/" = {
                extraConfig = ''
                  autoindex off;
                  root /var/local/www;
                '';
              };
            }
            // (lib.optionalAttrs (isProxied "grafana") {
              locations."/grafana/" = let
                grafanaCfg = config.my.containers.grafana;
              in {
                proxyPass = "http://${toString grafanaCfg.address}:${toString grafanaCfg.proxyPort}";
                proxyWebsockets = true;
                #recommendedProxySettings = true;
              };
            });

          appendHttpConfig =
            concatStringsSep "\n"
            (
              map (c: serverStanza c) (
                []
                ++ (lib.optionals (isProxied "gitea") [(getAttr "gitea" config.my.containers)])
                ++ (lib.optionals (isProxied "vault") [(getAttr "vault" config.my.containers)])
                ++ (lib.optionals (isProxied "seafile") [(getAttr "seafile" config.my.containers)])
              )
            );
        };

        services.resolved.enable = false;
        environment.variables.TZ = config.my.containerCommon.timezone;
        system.stateVersion = config.my.containerCommon.stateVersion;
      }; # config
    }; # container nginx
  };
}
