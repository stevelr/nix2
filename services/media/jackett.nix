# services/media/jackett.nix
{
  pkgs,
  unstable ? pkgs.unstable,
  lib ? pkgs.lib,
}: {
  mkService = cfg: let
    dataHome = "${cfg.storage.localBase}/data";
    cacheHome = "${cfg.storage.localBase}/cache";
    configHome = "${cfg.storage.localBase}/config";
  in {
    services = {
      jackett = {
        enable = cfg.enable && cfg.services.jackett.enable;
        description = "jackett service (${unstable.jackett.pname}-${unstable.jackett.version})";
        documentation = ["man:jackett(1)"];
        wants = ["network-online.target"];
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        path = [
          pkgs.bash
          unstable.jackett
        ];

        environment = {
          XDG_DATA_HOME = "${dataHome}";
          XDG_CONFIG_HOME = "${configHome}";
          XDG_CACHE_HOME = "${cacheHome}";
          TZ = cfg.timeZone;
        };

        serviceConfig = {
          Type = "exec";
          User = "jackett";
          Group = "media-group";
          UMask = "0007";

          ExecStartPre = let
            ensureDir = d: m: ''
              if ! test -d "${d}"; then
                mkdir -p "${d}"
                chmod ${m} "${d}"
                chown jackett:media-group "${d}"
              fi
            '';
            preStartScript = pkgs.writeScript "jackett-run-prestart" ''
              #!${pkgs.bash}/bin/bash
              # Create any essential directories if they don't exist
              ${ensureDir "${dataHome}/Jackett" "770"}
              ${ensureDir "${cacheHome}/Jackett" "700"}
              ${ensureDir "${configHome}/Jackett" "700"}
            '';
          in "!${preStartScript}";
          ExecStart = ''
            ${unstable.jackett}/bin/jackett \
              --Port ${toString cfg.services.jackett.proxyPort}
          '';
        };
      };
    };
  };
}
