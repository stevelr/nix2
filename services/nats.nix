{ config, pkgs, lib, ... }:
{
  services.nats = {
    enable = true;
    jetstream = true;
    port = config.my.ports.nats.port;
    serverName = "${config.my.hostName}-nats";
  };
}
