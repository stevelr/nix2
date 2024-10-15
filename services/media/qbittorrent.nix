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
    xdgData = "${cfg.storage.localBase}/data";
    cacheBase = "${cfg.storage.localBase}/cache";
    configBase = "${cfg.storage.localBase}/config";
    configPath = "${configBase}/qBittorrent/qBittorrent.conf";
    downloadDir = pkgs.myLib.valueOr cfg.storage.downloads "${cfg.storage.localBase}/downloads";
    webUiPort = config.my.ports.qbittorrent.port;
    vpnCfg = config.my.vpnNamespaces.${cfg.namespace};
  in {
    enable = cfg.enable && (builtins.elem "qbittorrent" cfg.backends);
    description = "qBittorrent-nox service";
    documentation = ["man:qbittorrent-nox(1)"];
    # this service runs inside the container,
    # and the container uses systemd after/requires/bindsTo to depend on the vpn service
    wants = ["network-online.target"];
    after = ["network.target"]; # ? nss-lookup.target
    wantedBy = ["multi-user.target"];

    environment = {
      QBT_WEBUI_PORT = toString webUiPort;
      XDG_DATA_HOME = "${xdgData}";
      XDG_CONFIG_HOME = "${configBase}";
      XDG_CACHE_HOME = "${cacheBase}";
      TZ = config.my.containerCommon.timezone; # shouold be UTC
    };

    path = with pkgs; [
      bash
      qbittorrent-nox
    ];

    serviceConfig = {
      Type = "exec";
      User = "qbittorrent";
      Group = "qbittorrent";

      # the following may be needed to bind to specific network interface (wg0)
      #AmbientCapabilities = "CAP_NET_RAW";

      ExecStartPre = let
        ensureDir = d: ''
          if ! test -d "${d}"; then
            mkdir -p "${d}"
            chmod 755 "${d}"
            chown qbittorrent:qbittorrent "${d}"
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
        '';
        preStartScript = pkgs.writeScript "qbittorrent-run-prestart" ''
          #!${pkgs.bash}/bin/bash
          ${ensureDir "${xdgData}/qBittorrent"}
          ${ensureDir "${cacheBase}/qBittorrent"}
          ${ensureDir "${configBase}/qBittorrent"}
          if ! test -f "${configPath}"; then
            cp "${defaultInit}" "${configPath}"
            chmod 644 "${configPath}"
            chown qbittorrent:qbittorrent "${configPath}"
          fi
        '';
      in "!${preStartScript}";
      ExecStart = "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox";
    };
  };
}
