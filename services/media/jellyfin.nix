# services/media/jellyfin.nix
{
  config,
  pkgs,
  lib ? pkgs.lib,
}: {
  # https://jellyfin.org/docs/general/administration/configuration/

  mkJellyfinService = cfg: let
    dataDir = "${cfg.storage.localBase}/data/jellyfin";
    configDir = "${cfg.storage.localBase}/config/jellyfin";
    cacheDir = "${cfg.storage.localBase}/cache/jellyfin";
    logDir = "${cfg.storage.localBase}/log/jellyfin";
  in {
    enable = cfg.enable && (builtins.elem "jellyfin" cfg.backends);
    description = "jellyfin service";
    documentation = ["man:jellyfin(1)"];
    # this service runs inside the container,
    # and the container uses systemd after/requires/bindsTo to depend on the vpn service
    wants = ["network-online.target"];
    after = ["network.target"];
    wantedBy = ["multi-user.target"];

    path = with pkgs; [
      bash
      jellyfin-ffmpeg
      jellyfin
      jellyfin-web
      #libva-utils # not sure if needed
    ];

    environment = {
      JELLYFIN_DATA_DIR = dataDir;
      JELLYFIN_CONFIG_DIR = configDir;
      JELLYFIN_CACHE_DIR = cacheDir;
      JELLYFIN_LOG_DIR = logDir;
      JELLYFIN_WEB_DIR = "${pkgs.jellyfin-web}/share/jellyfin-web";
      TZ = config.my.containerCommon.timezone; # shouold be UTC
    };

    serviceConfig = {
      Type = "exec";
      User = "jellyfin";
      Group = "jellyfin";

      ExecStartPre = let
        preStartScript = pkgs.writeScript "jellyfin-run-prestart" ''
          #!${pkgs.bash}/bin/bash
          # Create any essential directories if they don't exist
          for dir in "${dataDir}" "${configDir}" "${cacheDir}" "${logDir}"; do
            if ! test -d "$dir"; then
              echo "Creating directory: $dir"
              mkdir -p "$dir"
              chown -R jellyfin:media-group "$dir"
              chmod 775 "$dir"
            fi
          done
        '';
      in "!${preStartScript}";
      ExecStart = "${pkgs.jellyfin}/bin/jellyfin";
    };
  };
}
