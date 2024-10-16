# services/media/radarr.nix
{
  config,
  pkgs,
  lib ? pkgs.lib,
}: {
  mkRadarrService = cfg: let
    dataHome = "${cfg.storage.localBase}/data";
    cacheHome = "${cfg.storage.localBase}/cache";
    configHome = "${cfg.storage.localBase}/config";

    logDir = "${cfg.storage.localBase}/log/radarr";
  in {
    services = {
      radarr = {
        enable = cfg.enable && (builtins.elem "radarr" cfg.backends);
        description = "radarr service (${pkgs.radarr.pname}-${pkgs.radarr.version})";
        documentation = ["man:radarr(1)"];
        wants = ["network-online.target"];
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        path = with pkgs; [
          bash
          radarr
        ];

        environment = {
          XDG_DATA_HOME = "${dataHome}";
          XDG_CONFIG_HOME = "${configHome}";
          XDG_CACHE_HOME = "${cacheHome}";
          TZ = config.my.containerCommon.timezone; # shouold be UTC
        };

        serviceConfig = {
          Type = "exec";
          User = "radarr";
          Group = "media-group";
          UMask = "0007";

          ExecStartPre = let
            ensureDir = d: m: ''
              if ! test -d "${d}"; then
                mkdir -p "${d}"
                chmod ${m} "${d}"
                chown radarr:media-group "${d}"
              fi
            '';
            preStartScript = pkgs.writeScript "radarr-run-prestart" ''
              #!${pkgs.bash}/bin/bash
              # Create any essential directories if they don't exist
              ${ensureDir "${dataHome}/radarr" "770"}
              ${ensureDir "${cacheHome}/radarr" "700"}
              ${ensureDir "${configHome}/radarr" "700"}
            '';
          in "!${preStartScript}";
          ExecStart = "${pkgs.radarr}/bin/Radarr";
        };
      };
    };
  };
}
