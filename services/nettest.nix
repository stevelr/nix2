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
  inherit (pkgs.myLib) vpnContainerConfig;
  inherit (lib.attrsets) recursiveUpdate;
in {
  containers = lib.optionalAttrs cfg.enable {
    nettest =
      recursiveUpdate {
        autoStart = true;
        #privateNetwork = true;
        ephemeral = true;
        hostBridge = bridgeCfg.name;
        localAddress = "${cfg.address}/${toString bridgeCfg.prefixLen}";

        config = {
          environment.systemPackages = with pkgs;
            [
              hello
              helix
              bind.dnsutils
              nmap
            ]
            ++ (import ../modules/handy-tools.nix {inherit pkgs;}).full;

          services.resolved.enable = false;

          users.users.user = {
            uid = 1000;
            group = "users";
            isNormalUser = true;
            #packages = [ ];
          };

          environment.variables.TZ = config.my.containerCommon.timezone;
          system.stateVersion = config.my.containerCommon.stateVersion;
        };
      }
      # possibly run in vpn namespace
      (lib.optionalAttrs ((!isNull cfg.namespace) && config.my.vpnNamespaces.${cfg.namespace}.enable)
        (vpnContainerConfig config.my.vpnNamespaces.${cfg.namespace}));
  };
}
