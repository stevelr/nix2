# empty.nix - an empty container
# compare with empty-static.mix to see how to convert between dhcp and static
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs) myLib;
  name = "empty";
  cfg = myLib.configIf config.my.containers name;
  bridgeCfg = config.my.subnets.${cfg.bridge};
in {
  containers = lib.optionalAttrs cfg.enable {
    empty = {
      autoStart = true;
      privateNetwork = true;

      hostBridge = bridgeCfg.name;

      config = {
        environment.systemPackages = with pkgs; [
          hello
        ];
        networking = myLib.netDefaults cfg bridgeCfg;

        services.resolved.enable = false;

        environment.variables.TZ = config.my.containerCommon.timezone;
        system.stateVersion = config.my.containerCommon.stateVersion;
      }; # config
    }; # container
  };
}
