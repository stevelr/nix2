# pmail.nix
# test environment with bash shell to experiment w/ pass and protonmail bridge
{
  config,
  pkgs,
  lib,
  ...
}: let
  name = "pmail";
  cfg = myLib.configIf config.my.containers name;
  bridgeCfg = config.my.subnets.${cfg.bridge};
  inherit (pkgs) myLib;
  mkUsers = pkgs.myLib.mkUsers config.const.userids;
  mkGroups = pkgs.myLib.mkGroups config.const.userids;
in {
  containers = lib.optionalAttrs cfg.enable {
    pmail = {
      autoStart = true;
      privateNetwork = true;
      hostBridge = bridgeCfg.name;
      localAddress = "${cfg.address}/${toString bridgeCfg.prefixLen}";

      config = {
        environment.variables.TZ = config.my.containerCommon.timezone;

        environment.systemPackages = with pkgs; [
          bash
          curl # for testing
          hydroxide
          helix
          netcat # for testing
          nmap
          xorg.xauth # for ssh with X forwarding
          xorg.xeyes # for testing gui
        ];

        users.groups = mkGroups ["pmail"];
        users.users = lib.recursiveUpdate (mkUsers ["pmail"]) {
          pmail = {
            # extra attributes
            createHome = true; # system users don't usually have home dir
            home = "/home/pmail";
            shell = pkgs.bashInteractive; # system users don't usually have shell
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILum+8vDPzWTYjUdzNIT8TSQK83Av6ifXX52hnca3GUz steve@cilantro"
            ];
          };
        };

        services.openssh = {
          enable = true;
          settings.X11Forwarding = true;
        };

        networking =
          myLib.netDefaults cfg bridgeCfg
          // {
            # no fw for now until I understand how this all works
            firewall.enable = false;
          };

        services.resolved.enable = false;

        # enable debug logging for network
        systemd.services."systemd-networkd".environment.SYSTEMD_LOG_LEVEL = "debug";
        system.stateVersion = config.my.containerCommon.stateVersion;
      };
    };
  };
}
