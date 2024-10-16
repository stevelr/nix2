# services/media/qbittorrent.nix
{
  config,
  pkgs,
  lib ? pkgs.lib,
}: {
  # qbittorrent wrapper
  # The qbittorrent-nox package is intended for headless server environments,
  # and doesn't include UI components. It is entirely controlled by the web ui

  # systemd configuratio notes:
  # https://github.com/qbittorrent/qBittorrent/wiki/Running-qBittorrent-without-X-server-(WebUI-only,-systemd-service-set-up,-Ubuntu-15.04-or-newer)
  # ^ has notes about using fstab and systemd dependency on mount to ensure necessary volumes are mounted

  mkQbittorrentService = cfg: let
    dataHome = "${cfg.storage.localBase}/data";
    cacheHome = "${cfg.storage.localBase}/cache";
    configHome = "${cfg.storage.localBase}/config";
    configPath = "${configHome}/qBittorrent/qBittorrent.conf";
    downloadDir = pkgs.myLib.valueOr cfg.storage.downloads "${cfg.storage.localBase}/downloads";
    webUiPort = config.my.ports.qbittorrent.port;
    vpnCfg = config.my.vpnNamespaces.${cfg.namespace};
    myPkg = pkgs.qbittorrent-nox;
  in {
    services = {
      qbittorrent = {
        enable = cfg.enable && (builtins.elem "qbittorrent" cfg.backends);
        description = "qBittorrent (${myPkg.pname}-${myPkg.version})";
        documentation = ["man:qbittorrent-nox(1)"];
        wants = ["network-online.target"];
        after = ["network.target"]; # ? nss-lookup.target
        wantedBy = ["multi-user.target"];

        environment = {
          QBT_WEBUI_PORT = toString webUiPort;
          XDG_DATA_HOME = "${dataHome}";
          XDG_CONFIG_HOME = "${configHome}";
          XDG_CACHE_HOME = "${cacheHome}";
          TZ = config.my.containerCommon.timezone; # shouold be UTC
        };

        path = [
          pkgs.bash
          myPkg
        ];

        serviceConfig = {
          Type = "exec";
          User = "qbittorrent";
          Group = "media-group";
          UMask = "0007";

          # the following may be needed to bind to specific network interface (wg0)
          #AmbientCapabilities = "CAP_NET_RAW";

          ExecStartPre = let
            ensureDir = d: m: ''
              if ! test -d "${d}"; then
                mkdir -p "${d}"
                chmod ${m} "${d}"
                chown qbittorrent:media-group "${d}"
              fi
            '';
            defaultInit = pkgs.writeText "initial_qbittorrent.conf" ''
              [BitTorrent]
              Session\InterfaceAddress=${vpnCfg.wgIp4}
              Session\InterfaceName=wg0
              Session\TempPath=${downloadDir}/incomplete
              Session\DefaultSavePath=${downloadDir}

              [LegalNotice]
              Accepted=true

              [Preferences]
              Downloads\SavePath=${downloadDir}/
              Downloads\TempPath=${downloadDir}/incomplete/
              WebUI\Port=${toString webUiPort}
              WebUI\Address=*
              WebUI\AlternativeUIEnabled=false
              WebUI\CSRFProtection=true
              WebUI\ClickjackingProtection=true
              WebUI\SecureCookie=true
            '';
            preStartScript = pkgs.writeScript "qbittorrent-run-prestart" ''
              #!${pkgs.bash}/bin/bash
              ${ensureDir "${dataHome}/qBittorrent" "770"}
              ${ensureDir "${cacheHome}/qBittorrent" "700"}
              ${ensureDir "${configHome}/qBittorrent" "700"}
              if ! test -f "${configPath}"; then
                cp "${defaultInit}" "${configPath}"
                chmod 600 "${configPath}"
                chown qbittorrent:qbittorrent "${configPath}"
              fi
            '';
          in "!${preStartScript}";
          ExecStart = "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox";
        };
      };
    };
  };
}
