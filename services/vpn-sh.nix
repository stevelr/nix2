# vpn-sh.nix - shell inside vpn
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.myLib) vpnContainerConfig;
  inherit (lib.attrsets) recursiveUpdate;

  name = "vpn-sh";
  cfg = config.my.containers.${name};
in {
  containers."vpn-sh" =
    recursiveUpdate {
      config = {
        environment.systemPackages = with pkgs; [
          bind.dnsutils
          nmap
          helix
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
      (vpnContainerConfig config.my.vpnNamespaces.${cfg.namespace}));
}
