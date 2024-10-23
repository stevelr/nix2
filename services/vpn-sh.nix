# vpn-sh.nix - shell inside vpn
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs) myLib;
  inherit (lib.attrsets) recursiveUpdate;

  name = "vpn-sh";
  cfg = myLib.configIf config.my.containers name;
in {
  containers = lib.optionalAttrs cfg.enable {
    "vpn-sh" =
      recursiveUpdate
      {
        config = {
          environment.systemPackages = with pkgs; [
            bind.dnsutils
            helix
            nmap
          ];
          networking = {
            nftables.enable = true;
            firewall.enable = false;
            #useDHCP = lib.mkForce true; # dhcp-assigned ip address
          };
          services.resolved.enable = false;
          environment.variables.TZ = config.my.containerCommon.timezone;
          system.stateVersion = config.my.containerCommon.stateVersion;
        };
      }
      (lib.optionalAttrs ((!isNull cfg.namespace) && config.my.vpnNamespaces.${cfg.namespace}.enable)
        (myLib.vpnContainerConfig config.my.vpnNamespaces.${cfg.namespace}));
  };
}
