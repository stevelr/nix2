{
  config,
  pkgs,
  lib ? pkgs.lib,
  ...
}: let
  inherit (pkgs) myLib;
  cfg = myLib.configIf config.my.services "monitoring";
  defaultNet = "container-br0";

  mkExporter = name: net: {
    enable = true;
    user = "${name}-exporter";
    group = "exporters";
    port = config.const.ports."node-exporter".port;
    listenAddress = config.my.subnets.${net}.gateway;
  };
in {
  services = lib.optionalAttrs cfg.enable {
    prometheus = {
      enable = true;
      exporters = {
        node =
          (mkExporter "node" defaultNet)
          // {
            enabledCollectors = [
              "logind"
              "systemd"
            ];
          };
        # kea = (mkExporter "kea" defaultNet) // {
        #   enable = keaCtrlCfg.enable;
        #   targets = [ "http://127.0.0.1:${toString keaCtrlCfg.port}" ];
        # };
        #nginx = mkExporter "nginx" defaultNet;
        #smartctl = mkExporter "smartctl" defaultNet;
        #systemd = mkExporter "systemd" defaultNet;
        #unbound = mkExporter "unbound" defaultNet;
        #zfs = mkExporter "zfs" defaultNet;
      };
    };
  };
}
