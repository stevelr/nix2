# nettest.nix - conainer with some net test tools
{
  config,
  pkgs,
  lib,
  ...
}: let
  name = "nettest";
  cfg = myLib.configIf config.my.containers name;
  bridgeCfg = config.my.subnets.${cfg.bridge};
  inherit (pkgs) myLib;
in {
  containers = lib.optionalAttrs cfg.enable {
    nettest = {
      autoStart = true;
      privateNetwork = true;
      hostBridge = bridgeCfg.name;
      localAddress = "${cfg.address}/${toString bridgeCfg.prefixLen}";

      config = {
        environment.systemPackages = with pkgs;
          [
            hello
          ]
          ++ (import ../nixos/handy-tools.nix {inherit pkgs;}).full;

        services.openssh.enable = true;

        networking =
          myLib.netDefaults cfg bridgeCfg
          // {
            firewall.enable = true;
            firewall.allowedTCPPorts = [22];
          };

        services.resolved.enable = false;

        environment.variables.TZ = config.my.containerCommon.timezone;
        system.stateVersion = config.my.containerCommon.stateVersion;
      };
    };
  };
}
