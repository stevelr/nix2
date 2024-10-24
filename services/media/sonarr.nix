# services/media/sonarr.nix
#
# TODO:
# add health check
# see https://www.medo64.com/2019/01/systemd-watchdog-for-any-service/
# use NotifyAccess=exec if using ExecStartPost, more secure than NotifyAccess=all
#
# if [[ $(curl -sL "http://localhost:${PORT:-8989}/ping" | jq -r '.status' 2>/dev/null) = "OK" ]]; then
#     exit 0
# else
#     exit 1
# fi
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
      sonarr = {
        enable = cfg.enable && cfg.services.sonarr.enable;
        description = "sonarr service (${pkgs.sonarr.pname}-${pkgs.sonarr.version})";
        documentation = ["man:sonarr(1)"];
        wants = ["network-online.target"];
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        path = [
          pkgs.bash
          pkgs.sonarr
        ];

        environment = {
          XDG_DATA_HOME = "${dataHome}";
          XDG_CONFIG_HOME = "${configHome}";
          XDG_CACHE_HOME = "${cacheHome}";
          TZ = cfg.timeZone;
        };

        serviceConfig = {
          Type = "exec";
          User = "sonarr";
          Group = "media-group";
          UMask = "0007";

          ExecStartPre = let
            ensureDir = d: m: ''
              if ! test -d "${d}"; then
                mkdir -p "${d}"
                chmod ${m} "${d}"
                chown sonarr:media-group "${d}"
              fi
            '';
            preStartScript = pkgs.writeScript "sonarr-run-prestart" ''
              #!${pkgs.bash}/bin/bash
              # Create any essential directories if they don't exist
              ${ensureDir "${dataHome}/Sonarr" "770"}
              ${ensureDir "${cacheHome}/Sonarr" "700"}
              ${ensureDir "${configHome}/Sonarr" "700"}
            '';
          in "!${preStartScript}";
          ExecStart = "${pkgs.sonarr}/bin/Sonarr";
        };
      };
    };
  };
}
