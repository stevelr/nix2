# gitea.nix
# last updated 2024-07-09
{
  config,
  pkgs,
  lib,
  ...
}: let
  name = "grafana";
  inherit (pkgs) myLib;
  cfg = myLib.configIf config.my.containers name;
  bridgeCfg = config.my.subnets.${cfg.bridge};
  mkUsers = myLib.mkUsers config.const.userids;
  mkGroups = myLib.mkGroups config.const.userids;
in {
  containers = lib.optionalAttrs cfg.enable {
    grafana = {
      autoStart = true;
      bindMounts = {
        "/var/lib/grafana" = {
          hostPath = "/var/lib/grafana";
          isReadOnly = false;
        };
      };
      privateNetwork = true;
      hostBridge = bridgeCfg.name;
      localAddress = "${cfg.address}/${toString bridgeCfg.prefixLen}";

      config = {
        services.grafana = {
          enable = true;
          # see https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/
          settings = {
            server = {
              # Listening Address
              http_addr = "0.0.0.0";
              # and Port
              http_port = cfg.proxyPort;
              # Grafana needs to know on which domain and URL it's running
              domain = "pangea.pasilla.net";
              # when using nginx and subpath, subpath must be at the end of this root_url
              root_url = "https://pangea.pasilla.net/grafana/";
              serve_from_sub_path = true;
              enable_gzip = true;
            };
            database = {
              # for simplicity to get running; change later
              type = "sqlite3";
            };
            analytics = {
              reporting_enabled = false;
              check_for_updates = false;
              check_for_plugin_updates = false;
            };
          };
        };

        environment.variables.TZ = config.my.containerCommon.timezone;
        users.users = mkUsers ["grafana"];
        users.groups = mkGroups ["grafana"];

        networking =
          myLib.netDefaults cfg bridgeCfg
          // {
            firewall.enable = true;
            firewall.allowedTCPPorts = [cfg.proxyPort];
          };
        # force br0 nameserver
        services.resolved.enable = false;
        system.stateVersion = config.my.containerCommon.stateVersion;
      }; # config
    };
  };
}
