# services/media/audiobookshelf.nix
{
  config,
  pkgs,
  lib ? pkgs.lib,
}: {
  mkAudiobookshelfService = cfg: let
    dataHome = "${cfg.storage.localBase}/data";
    cacheHome = "${cfg.storage.localBase}/cache";
    configHome = "${cfg.storage.localBase}/config";
    logDir = "${cfg.storage.localBase}/log/sonarr";
  in {
    services = {
      audiobookshelf = {
        enable = cfg.enable && (builtins.elem "audiobookshelf" cfg.backends);
        description = "audiobookshelf service (${pkgs.audiobookshelf.pname}-${pkgs.audiobookshelf.version})";
        documentation = ["man:audiobookshelf(1)"];
        wants = ["network-online.target"];
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        path = with pkgs; [
          bash
          audiobookshelf
        ];

        environment = {
          XDG_DATA_HOME = "${dataHome}";
          XDG_CONFIG_HOME = "${configHome}";
          XDG_CACHE_HOME = "${cacheHome}";
          TZ = config.my.containerCommon.timezone; # shouold be UTC
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
          ExecStart = "${pkgs.audiobookshelf}/bin/audiobookshelf";
        };
      };
    };
  };
}
