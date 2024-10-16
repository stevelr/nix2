# services/media/jackett.nix
{
  config,
  pkgs,
  lib ? pkgs.lib,
}: {
  mkJackettService = cfg: let
    dataHome = "${cfg.storage.localBase}/data";
    cacheHome = "${cfg.storage.localBase}/cache";
    configHome = "${cfg.storage.localBase}/config";
    #logDir = "${cfg.storage.localBase}/log/jackett";
  in {
    services = {
      jackett = {
        enable = cfg.enable && (builtins.elem "jackett" cfg.backends);
        description = "jackett service (${pkgs.jackett.pname}-${pkgs.jackett.version})";
        documentation = ["man:jackett(1)"];
        wants = ["network-online.target"];
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        path = with pkgs; [
          bash
          jackett
        ];

        environment = {
          XDG_DATA_HOME = "${dataHome}";
          XDG_CONFIG_HOME = "${configHome}";
          XDG_CACHE_HOME = "${cacheHome}";
          TZ = config.my.containerCommon.timezone; # shouold be UTC
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
              ${ensureDir "${dataHome}/jackett" "770"}
              ${ensureDir "${cacheHome}/jackett" "700"}
              ${ensureDir "${configHome}/jackett" "700"}
            '';
          in "!${preStartScript}";
          ExecStart = "${pkgs.jackett}/bin/jackett";
        };
      };
    };
  };
}
