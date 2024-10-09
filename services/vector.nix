# Vector
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.my.containers.vector;
  bridgeCfg = config.my.subnets.${cfg.bridge};
  clickhouse = config.my.containers.clickhouse;
  inherit (pkgs) myLib;

  dataDir = "/var/lib/vector";
  configSrc = "/home/steve/project/ops/containers/vector";
  configYaml = builtins.readFile "${configSrc}/config.yaml";

  package = pkgs.unstable.vector;
  mkUsers = myLib.mkUsers config.my.userids;
  mkGroups = myLib.mkGroups config.my.userids;
in
  lib.optionalAttrs cfg.enable {
    containers.vector = {
      autoStart = true;
      privateNetwork = true;
      bindMounts = {
        "${dataDir}" = {
          hostPath = "/var/lib/vector";
          isReadOnly = false;
        };
      };
      hostBridge = bridgeCfg.name;
      localAddress = "${cfg.address}/${toString bridgeCfg.prefixLen}";
      forwardPorts = [
        {
          hostPort = cfg.settings.apiPort;
          containerPort = cfg.settings.apiPort;
        }
      ];

      config = let
        scrapeSrc = ip: port: {
          type = "prometheus_scrape";
          endpoint = "http://${ip}:${toString port}/metrics";
        };
        metrics = port: "http://10.135.1.2:${toString port}/metrics";
        settings = {
          data_dir = dataDir;
          api = {
            enabled = true;
            address = "0.0.0.0:${toString cfg.settings.apiPort}";
          };
          sources = let
            ctr = config.my.containers;
          in {
            kea = scrapeSrc config.my.subnets."container-br0".gateway 9547;
            nginx = scrapeSrc ctr.nginx.address 9113;
            node = scrapeSrc 9100;
            smartctl = scrapeSrc 9644;
            systemd = scrapeSrc 9558;
            unbound = scrapeSrc 9167;
            zfs = scrapeSrc 9134;
          };
          sinks = {
            clickhouse = {
              type = "clickhouse";
              inputs = ["kea" "nginx" "node" "smartctl" "systemd" "unbound" "zfs"];
              endpoint = "http://${clickhouse.address}:${clickhouse.settings.http}";
              table = "promdata";
            };
          };
        };
        format = pkgs.formats.toml {};
        conf = format.generate "vector.toml" settings;
        validateConfig = file:
          pkgs.runCommand "validate-vector-conf" {
            nativeBuildInputs = [pkgs.vector];
          } ''
            vector validate --no-environment "${file}"
            ln -s "${file}" "$out"
          '';
      in {
        environment.systemPackages = [package];
        networking =
          myLib.netDefaults cfg bridgeCfg
          // {
            firewall.allowedTCPPorts = [
              cfg.settings.apiPort
            ];
          };

        systemd.services.vector = {
          description = "Vector event and log aggregator";
          after = ["network.target"];
          requires = ["network.target"];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "notify";
            User = "vector";
            Group = "vector";
            Restart = "always";
            StateDirectory = "vector";
            LogsDirectory = "vector";
            TimeoutStartSec = "infinity";
            ExecStart = "${lib.getExe package} --config ${validateConfig conf}";
            ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
          };
          unitConfig = {
            StartLimitIntervalSec = 10;
            StartLimitBurst = 5;
          };
          environment = {};
        };
        users.users = mkUsers ["vector"];
        users.groups = mkGroups ["vector"];

        environment.etc = {
          "vector/config.yaml".text = configYaml;
        };
        services.resolved.enable = false;
        environment.variables.TZ = config.my.containerCommon.timezone;
        system.stateVersion = 24.05; # config.my.containerCommon.stateVersion;
      }; # config
    }; # container
  }
