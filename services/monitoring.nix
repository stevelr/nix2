{config, ...}: let
  collectorIp = config.my.subnets."container-br0".gateway;
  #keaCtrlCfg = config.my.service.kea.control-agent;

  mkExporter = name: {
    enable = true;
    user = "${name}-exporter";
    group = "exporters";
    port = config.my.ports."node-exporter".port;
    listenAddress = collectorIp;
  };
in {
  services.prometheus = {
    enable = true;
    exporters = {
      node =
        (mkExporter "node")
        // {
          enabledCollectors = [
            "logind"
            "systemd"
          ];
        };
      # kea = (mkExporter "kea") // {
      #   enable = keaCtrlCfg.enable;
      #   targets = [ "http://127.0.0.1:${toString keaCtrlCfg.port}" ];
      # };
      #nginx = mkExporter "nginx";
      #smartctl = mkExporter "smartctl";
      #systemd = mkExporter "systemd";
      #unbound = mkExporter "unbound";
      #zfs = mkExporter "zfs";
    };
  };
}
