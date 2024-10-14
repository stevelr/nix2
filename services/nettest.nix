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
        ephemeral = true;
        #hostBridge = bridgeCfg.name;
        #localAddress = "${cfg.address}/${toString bridgeCfg.prefixLen}";

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
          services.openssh = {
            enable = true;
            listenAddresses = [
              {
                addr = "192.168.10.11";
                port = 22;
              }
            ];
            settings = {
              PermitRootLogin = "no";
              X11Forwarding = true;
            };
            #startWhenNeeded = true;
          };
          networking.nftables.enable = true;

          users.users.user = {
            uid = 1000;
            group = "users";
            isNormalUser = true;
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
