{
  config,
  pkgs,
  lib,
  ...
}: {
  services.nats = {
    enable = false;
    jetstream = true;
    port = config.my.ports.nats.port;
    serverName = "${config.my.hostName}-nats";
  };
}
