# services/media/audiobookshelf.nix
{
  #config,
  pkgs,
  unstable ? pkgs.unstable,
  lib ? pkgs.lib,
}: {
  mkAudiobookshelfService = cfg: let
    dataHome = "${cfg.storage.localBase}/data";
    cacheHome = "${cfg.storage.localBase}/cache";
    configHome = "${cfg.storage.localBase}/config";
  in {
    services = {
      audiobookshelf = {
        enable = cfg.enable && cfg.services.audiobookshelf.enable;
        description = "audiobookshelf service (${unstable.audiobookshelf.pname}-${unstable.audiobookshelf.version})";
        documentation = ["man:audiobookshelf(1)"];
        wants = ["network-online.target"];
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        path = [
          pkgs.bash
          unstable.audiobookshelf
        ];

        environment = {
          XDG_DATA_HOME = "${dataHome}";
          XDG_CONFIG_HOME = "${configHome}";
          XDG_CACHE_HOME = "${cacheHome}";
          TZ = cfg.timeZone;
        };

        serviceConfig = {
          Type = "exec";
          User = "audiobookshelf";
          Group = "media-group";
          UMask = "0007";

          ExecStartPre = let
            ensureDir = d: m: ''
              if ! test -d "${d}"; then
                mkdir -p "${d}"
                chmod ${m} "${d}"
                chown audiobookshelf:media-group "${d}"
              fi
            '';
            preStartScript = pkgs.writeScript "audiobookshelf-run-prestart" ''
              #!${pkgs.bash}/bin/bash
              # Create any essential directories if they don't exist
              ${ensureDir "${dataHome}/audiobookshelf" "770"}
              ${ensureDir "${cacheHome}/audiobookshelf" "700"}
              ${ensureDir "${configHome}/audiobookshelf" "700"}
            '';
          in "!${preStartScript}";
          ExecStart = ''
            ${unstable.audiobookshelf}/bin/audiobookshelf \
               --metadata ${dataHome}/audiobookshelf \
               --config ${configHome}/audiobookshelf \
               --port ${toString cfg.services.audiobookshelf.proxyPort}
          '';
        };
      };
    };
  };
}
