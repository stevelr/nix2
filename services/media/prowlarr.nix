# services/media/prowlarr.nix
{
  config,
  pkgs,
  lib ? pkgs.lib,
}: {
  mkProwlarrService = cfg: let
    dataHome = "${cfg.storage.localBase}/data";
    cacheHome = "${cfg.storage.localBase}/cache";
    configHome = "${cfg.storage.localBase}/config";
    #logDir = "${cfg.storage.localBase}/log/prowlarr";
  in {
    services = {
      prowlarr = {
        enable = cfg.enable && (builtins.elem "prowlarr" cfg.backends);
        description = "prowlarr service (${pkgs.prowlarr.pname}-${pkgs.prowlarr.version})";
        documentation = ["man:prowlarr(1)"];
        wants = ["network-online.target"];
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        path = with pkgs; [
          bash
          prowlarr
        ];

        environment = {
          XDG_DATA_HOME = "${dataHome}";
          XDG_CONFIG_HOME = "${configHome}";
          XDG_CACHE_HOME = "${cacheHome}";
          TZ = config.my.containerCommon.timezone; # shouold be UTC
        };

        serviceConfig = {
          Type = "exec";
          User = "prowlarr";
          Group = "media-group";
          UMask = "0007";

          ExecStartPre = let
            ensureDir = d: m: ''
              if ! test -d "${d}"; then
                mkdir -p "${d}"
                chmod ${m} "${d}"
                chown prowlarr:media-group "${d}"
              fi
            '';
            preStartScript = pkgs.writeScript "prowlarr-run-prestart" ''
              #!${pkgs.bash}/bin/bash
              # Create any essential directories if they don't exist
              ${ensureDir "${dataHome}/prowlarr" "770"}
              ${ensureDir "${cacheHome}/prowlarr" "700"}
              ${ensureDir "${configHome}/prowlarr" "700"}
            '';
          in "!${preStartScript}";
          ExecStart = "${pkgs.prowlarr}/bin/Prowlarr";
        };
      };
    };
  };
}
