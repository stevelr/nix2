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
    services = {
      jellyfin = {
        enable = cfg.enable && (builtins.elem "jellyfin" cfg.backends);
        description = "jellyfin service (${pkgs.jellyfin.pname}-${pkgs.jellyfin.version})";
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
          Group = "media-group";
          UMask = "0007";

          ExecStartPre = let
            ensureDir = d: m: ''
              if ! test -d "${d}"; then
                mkdir -p "${d}"
                chmod ${m} "${d}"
                chown jellyfin:media-group "${d}"
              fi
            '';
            preStartScript = pkgs.writeScript "jellyfin-run-prestart" ''
              #!${pkgs.bash}/bin/bash
              # Create any essential directories if they don't exist
              ${ensureDir "${dataDir}" "770"}
              ${ensureDir "${configDir}" "700"}
              ${ensureDir "${cacheDir}" "700"}
              ${ensureDir "${logDir}" "700"}
            '';
          in "!${preStartScript}";
          ExecStart = "${pkgs.jellyfin}/bin/jellyfin";
        };
      };
    };
  };
}
