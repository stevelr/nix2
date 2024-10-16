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
  config,
  pkgs,
  lib ? pkgs.lib,
}: {
  mkSonarrService = cfg: let
    dataHome = "${cfg.storage.localBase}/data";
    cacheHome = "${cfg.storage.localBase}/cache";
    configHome = "${cfg.storage.localBase}/config";
    logDir = "${cfg.storage.localBase}/log/sonarr";
  in {
    services = {
      sonarr = {
        enable = cfg.enable && (builtins.elem "sonarr" cfg.backends);
        description = "sonarr service (${pkgs.sonarr.pname}-${pkgs.sonarr.version})";
        documentation = ["man:sonarr(1)"];
        wants = ["network-online.target"];
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        path = with pkgs; [
          bash
          sonarr
        ];

        environment = {
          XDG_DATA_HOME = "${dataHome}";
          XDG_CONFIG_HOME = "${configHome}";
          XDG_CACHE_HOME = "${cacheHome}";
          TZ = config.my.containerCommon.timezone; # shouold be UTC
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
