{
  config,
  pkgs,
  lib,
  ...
}: {
  services.nats = {
    enable = false;
    jetstream = true;
    port = config.const.ports.nats.port;
    serverName = "${config.my.hostName}-nats";
  };
}
