{
  cfg,
  pkgs,
  ...
}: let
  # programs
  curl = "${pkgs.curl}/bin/curl";
  ip = "${pkgs.iproute2}/bin/ip";
  sed = "${pkgs.gnused}/bin/sed";
  natpmp = "${pkgs.packages.py-natpmp}/bin/natpmp-client.py";
  jq = "${pkgs.jq}/bin/jq";
  nc = "${pkgs.netcat}/bin/nc";
  logger = "${pkgs.util-linux}/bin/logger";
  log-error = "${logger} -s -p err";
  #log-warning = "${logger} -p warning";
  log-notice = "${logger} -s -p notice";
  #log-info = "${logger} -p info";
  log-debug = "${logger} -p debug";

  getExternalIP = pkgs.writeShellScriptBin "get-external-ip" ''
    ${curl} -sL https://icanhazip.com
  '';

  vpnCheck = pkgs.writeShellScriptBin "vpn-check" ''
    # confirm vpn is running.
    # check first check default route, then check connectivity to provider's dns server in tunnel
    # if vpn is not up, displays message and exits with error status.
    # if vpn is up, no output is generated, unless the -v (verbose) flag is provided
    route_if=$(${ip} route get 9.9.9.9 | tr -d '\r\n' | ${sed} -E 's/.* dev ([a-z0-9]+)+ .*$/\1/')
    if [ "$route_if" != "wg0" ]; then
      ${log-error} "Error: VPN not active (using $route_if) - quitting"
      exit 1
    fi
    # check dns connectivity (using TCP)
    ${nc} -w1 -z ${cfg.vpn.wgGateway} 53 2>/dev/null \
        || ( ${log-error} "Error: failed to connect to vpn dns server" && exit 1 )

    if [ "$1" = "-v" ]; then
      echo "VPN ok"
    fi
  '';

  fixPortForward = let
    get-external-ip = "${getExternalIP}/bin/get-external-ip";
    vpn-check = "${vpnCheck}/bin/vpn-check";
  in
    pkgs.writeShellScriptBin "fix-port-forward" ''
      # check ProtonVPN external port and adjust qbittorrent external port if necessary
      set -eu

      # ip address and port of qbittorrent (web) api.
      QBITTORRENT_ADDR=http://127.0.0.1:${toString cfg.services.qbittorrent.proxyPort}
      # ip address of proton vpn router. According to the docs, this doesn't change
      VPN_GATEWAY=${toString cfg.vpn.wgGateway}

      # make sure vpn is running
      ${vpn-check}

      DATE=$(date -Iseconds)

      vpn_ip=$(${get-external-ip})
      nat_port=$(${natpmp} -g $VPN_GATEWAY 0 0 | ${sed} -E 's/^.* private_port ([0-9]+).*$/\1/')
      qbt_port=$(${curl} -s $QBITTORRENT_ADDR/api/v2/app/preferences | ${jq} '.listen_port')

      if [ "$nat_port" != "$qbt_port" ]; then
        from_port=$qbt_port
        echo "json={\"listen_port\":$nat_port}" | ${curl} -s --data @- $QBITTORRENT_ADDR/api/v2/app/setPreferences

        # test to confirm change
        qbt_port=$(${curl} -s $QBITTORRENT_ADDR/api/v2/app/preferences | ${jq} '.listen_port')

        if [ "$nat_port" != "$qbt_port" ]; then
          ${log-error} Error: failed to change nat-pmp port qbt=$qbt_port nat=$nat_port
          status="error:$nat_port:$qbt_port"
        else
          ${log-notice} changed nat-pmp port from $from_port to $nat_port
          status="changed"
        fi
      else
        ${log-debug} nat-pmp no change qbt=$qbt_port ip=$vpn_ip
        status="no-change"
      fi

      # cat <<_OUT
      # {"timestamp":"$DATE","nat_port":$nat_port,"status":"$status","vpn_ip":"$vpn_ip","route_if":"$route_if"}
      # _OUT
    '';
in {
  inherit getExternalIP vpnCheck fixPortForward;
}
