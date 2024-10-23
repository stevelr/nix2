# gitea.nix
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs) myLib;
  name = "gitea";
  bridgeCfg = config.my.subnets.${cfg.bridge};
  cfg = myLib.configIf config.my.containers name;
  mkUsers = myLib.mkUsers config.const.userids;
  mkGroups = myLib.mkGroups config.const.userids;
in {
  containers = lib.optionalAttrs cfg.enable {
    gitea = {
      autoStart = true;
      bindMounts = {
        "/var/lib/db/pg-gitea1" = {
          hostPath = "/var/lib/db/pg-gitea1";
          isReadOnly = false;
        };
        "/var/lib/gitea" = {
          hostPath = "/var/lib/gitea";
          isReadOnly = false;
        };
      };
      privateNetwork = true;
      hostBridge = bridgeCfg.name;
      localAddress = "${cfg.address}/${toString bridgeCfg.prefixLen}";
      forwardPorts = [
        {
          hostPort = cfg.settings.hostSsh;
          containerPort = cfg.settings.ssh;
        }
      ];
      path = null;

      config = {
        users.users = mkUsers ["gitea" "postgres"];
        users.groups = mkGroups ["gitea" "postgres"];

        # debug logging for network
        systemd.services."systemd-networkd".environment.SYSTEMD_LOG_LEVEL = "debug";

        environment.variables.TZ = config.my.containerCommon.timezone;

        environment.systemPackages = with pkgs; [
          #
        ];

        services.postgresql = {
          enable = true;
          enableTCPIP = false; # false: only open unix domain socket
          package = pkgs.postgresql_16;
          settings.port = 5432;
          dataDir = "/var/lib/db/pg-gitea1";
          initdbArgs = ["--no-locale" "-E=UTF8" "-n" "-N"];
          #ensureDatabases = [ "gitea" ];
          ensureUsers = [
            {
              name = "gitea";
              #ensureDBOwnership = true;
            }
          ];
        };

        # all these storage locations are configurable. Currently all subdirs of stateDir /var/lib/gitea
        # repositoryRoot   /var/lib/gitea/repositories
        # static files in  /var/lib/gitea/data
        # log files in     /var/lib/gitea/log
        # custom (config & templates) in /var/lib/gitea/custom
        services.gitea = {
          enable = true;
          user = "gitea";
          group = "gitea";
          stateDir = "/var/lib/gitea";
          settings.server = {
            DOMAIN = "gitea";
            HTTP_PORT = cfg.proxyPort;
            ROOT_URL = "https://gitea.pasilla.net/";
            SSH_PORT = cfg.settings.hostSsh;
            SSH_LISTEN_PORT = cfg.settings.ssh;
            START_SSH_SERVER = true;
            PROTOCOL = "http"; # TODO make https, then set settings.session.COOKIE_SECURE
            # session.COOKIE_SECURE  ;
          };
          database = {
            type = "postgres";
            # documentation is incorrect - this is a directory, not the actual file
            socket = "/run/postgresql";
            # name = "gitea";
            # createDatabase = true;
            # user = "gitea"
          };
        };

        networking =
          myLib.netDefaults cfg bridgeCfg
          // {
            firewall.enable = true;
            firewall.allowedTCPPorts = [cfg.proxyPort cfg.settings.ssh];
          };

        # force br0 nameserver
        services.resolved.enable = false;

        system.stateVersion = config.my.containerCommon.stateVersion;
      }; # config
    }; # container pg-gitea
  };
}
