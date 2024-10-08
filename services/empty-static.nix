# empty-static.nix - an empty container with static ip address
# compare with empty.mix to see how to convert between dhcp and static
{
  config,
  pkgs,
  lib,
  ...
}: let
  name = "empty-static";
  cfg = myLib.configIf config.my.containers name;
  bridgeCfg = config.my.subnets.${cfg.bridge};
  inherit (pkgs) myLib;
in {
  containers = lib.optionalAttrs cfg.enable {
    "empty-static" = {
      autoStart = true;
      privateNetwork = true;

      hostBridge = bridgeCfg.name;
      localAddress = "${cfg.address}/${toString bridgeCfg.prefixLen}";

      config = {
        environment.systemPackages = with pkgs; [
          hello
        ];
        networking =
          myLib.netDefaults cfg bridgeCfg
          // {
            defaultGateway = config.my.subnets."container-br0".gateway;
          };

        services.resolved.enable = false;

        environment.variables.TZ = config.my.containerCommon.timezone;
        system.stateVersion = config.my.containerCommon.stateVersion;
      }; # config
    }; # container
  };
}
