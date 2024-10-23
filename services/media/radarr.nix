# services/media/radarr.nix
{
  pkgs,
  lib ? pkgs.lib,
}: {
  mkService = cfg: let
    dataHome = "${cfg.storage.localBase}/data";
    cacheHome = "${cfg.storage.localBase}/cache";
    configHome = "${cfg.storage.localBase}/config";
  in {
    services = {
      radarr = {
        enable = cfg.enable && cfg.services.radarr.enable;
        description = "radarr service (${pkgs.radarr.pname}-${pkgs.radarr.version})";
        documentation = ["man:radarr(1)"];
        wants = ["network-online.target"];
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        path = [
          pkgs.bash
          pkgs.radarr
        ];

        environment = {
          XDG_DATA_HOME = "${dataHome}";
          XDG_CONFIG_HOME = "${configHome}";
          XDG_CACHE_HOME = "${cacheHome}";
          TZ = cfg.timeZone;
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
              ${ensureDir "${dataHome}/Radarr" "770"}
              ${ensureDir "${cacheHome}/Radarr" "700"}
              ${ensureDir "${configHome}/Radarr" "700"}
            '';
          in "!${preStartScript}";
          ExecStart = "${pkgs.radarr}/bin/Radarr";
        };
      };
    };
  };
}
