# Clickhouse container
# Runs clickhouse in podman container as a systemd service
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.myLib) configIf netDefaults;

  cfg = configIf config.my.containers "clickhouse";
  bridgeCfg = config.my.subnets.${cfg.bridge};

  #image = "docker.io/altinity/clickhouse-server:24.3.5.48.altinityfips";
  configXml = builtins.readFile "./config.xml";
  usersXml = builtins.readFile "./users.xml";

  package = pkgs.clickhouse;
  mkUsers = pkgs.myLib.mkUsers config.my.userids;
  mkGroups = pkgs.myLib.mkGroups config.my.userids;
in {
  config.containers = lib.optionalAttrs cfg.enable {
    clickhouse = {
      autoStart = true;
      privateNetwork = true;
      bindMounts = {
        "/var/lib/clickhouse" = {
          hostPath = "/var/lib/db/ch-ops";
          isReadOnly = false;
        };
      };
      path = null;
      hostBridge = bridgeCfg.name;
      localAddress = "${cfg.address}/${toString bridgeCfg.prefixLen}";
      forwardPorts = [
        {
          hostPort = cfg.settings.httpPort;
          containerPort = cfg.settings.httpPort;
        }
        {
          hostPort = cfg.settings.tcpPort;
          containerPort = cfg.settings.tcpPort;
        }
      ];

      config = {
        environment.systemPackages = [package];
        networking =
          netDefaults cfg bridgeCfg
          // {
            firewall.allowedTCPPorts = [
              cfg.settings.httpPort
              cfg.settings.tcpPort
            ];
          };

        systemd.services.clickhouse = {
          description = "Clickhouse database server";
          after = ["network.target"];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "notify";
            User = "clickhouse";
            Group = "clickhouse";
            #Restart = "on-failure";
            ConfigurationDirectory = "clickhouse-server";
            AmbientCapabilities = "CAP_SYS_NICE";
            StateDirectory = "clickhouse";
            LogsDirectory = "clickhouse";
            TimeoutStartSec = "infinity";
            ExecStart = "${package}/bin/clickhouse-server --config-file=/etc/clickhouse-server/config.xml";
            #TimeoutStopSec = 70;
          };
          environment = {
            # watchdog must be off for sd_notify to work correctly
            CLICKHOUSE_WATCHDOG_ENABLE = "0";
          };
        };
        users.users = mkUsers ["clickhouse"];
        users.groups = mkGroups ["clickhouse"];

        environment.etc = {
          "clickhouse-server/config.xml".text = configXml;
          "clickhouse-server/users.xml".text = usersXml;
        };
        services.resolved.enable = false;
        environment.variables.TZ = config.my.containerCommon.timezone;
        system.stateVersion = config.my.containerCommon.stateVersion;
      }; # config
    }; # container
  };
}
