# services/media/jellyfin.nix
{
  pkgs,
  unstable ? pkgs.unstable,
  lib ? pkgs.lib,
}: {
  # https://jellyfin.org/docs/general/administration/configuration/

  mkService = cfg: let
    dataDir = "${cfg.storage.localBase}/data/jellyfin";
    configDir = "${cfg.storage.localBase}/config/jellyfin";
    cacheDir = "${cfg.storage.localBase}/cache/jellyfin";
    logDir = "${cfg.storage.localBase}/log/jellyfin";
  in {
    services = {
      jellyfin = {
        enable = cfg.enable && cfg.services.jellyfin.enable;
        description = "jellyfin service (${unstable.jellyfin.pname}-${unstable.jellyfin.version})";
        documentation = ["man:jellyfin(1)"];
        # this service runs inside the container,
        # and the container uses systemd after/requires/bindsTo to depend on the vpn service
        wants = ["network-online.target"];
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        path = [
          pkgs.bash
          unstable.jellyfin-ffmpeg
          unstable.jellyfin
          unstable.jellyfin-web
          #libva-utils # not sure if needed
        ];

        environment = {
          JELLYFIN_DATA_DIR = dataDir;
          JELLYFIN_CONFIG_DIR = configDir;
          JELLYFIN_CACHE_DIR = cacheDir;
          JELLYFIN_LOG_DIR = logDir;
          JELLYFIN_WEB_DIR = "${unstable.jellyfin-web}/share/jellyfin-web";
          TZ = cfg.timeZone; # shouold be UTC
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
          ExecStart = "${unstable.jellyfin}/bin/jellyfin";
        };
      };
    };
  };
}
