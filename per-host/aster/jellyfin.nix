{
  config,
  pkgs,
  lib,
  ...
}: let
  hostAddress = "10.10.0.1";
in {
  containers.jellyfin = {
    inherit hostAddress;

    autoStart = true;
    enableTun = true;
    privateNetwork = true;
      bindMounts = {
        "/jdata" = {
          hostPath = "/tmp/jdata";
          isReadOnly = false;
        };
      };
    config = {
      config,
      stdenv,
      ...
    }: {
      config = {
        nixpkgs.pkgs = pkgs;
        networking.firewall.enable = false;
        environment.systemPackages = with pkgs; [
          yq
          yj
          jq
          git
          vim
          tree
        ];
        services.jellyfin.enable = true;
        services.sonarr.enable = true;
      };
    };
  }
}
