# wgrouter.nix
#
# Set up wireguard vpn and network namespace.
#
# To use:
# (1) Add vpn definition to  my.config.vpnNamespaces. The attribute name is the namespace name.
# (2) For each vpn, store config file (with private key) at /etc/router/${ns}/wg.conf (on the host)
# (3) For each container to route through the vpn, set my.config.container.<name>.namespace= ns-name,
#     and surround container def like this:
#     let
#        cfg = config.my.containers."my-container";
#     in
#     containers."my-container" = lib.recursiveUpdate {
#          config = { ... }
#     }
#     (vpnContainerConfig config.my.vpnNamespaces.${cfg.namespace}));
# (4) on host, set boot.kernel.sysctl = { "net.ipv4.ip_forward" = 1; };
#
# currently supports ipv4 only
#
# TODO: add health check for vpn
#    leaktest: curl -o dnsleaktest.sh -s https://raw.githubusercontent.com/macvk/dnsleaktest/b03ab54d574adbe322ca48cbcb0523be720ad38d/dnsleaktest.sh
#       sh ./dnsleaktest.sh
#     iptest: curl -s ipinfo.io
#
# TODO: don't have network connectivity from host, for example, if container runs sshd, can't ssh to it. Needs debugging. OTOH, lack of network connectivity is good because we know there are no leaks
{
  config,
  pkgs,
  lib ? pkgs.lib,
  ...
}:
# Any host that runs vpn must set
let
  inherit (builtins) filter;
  inherit (lib) listToAttrs attrValues;
  inherit (pkgs.myLib) valueOr;

  # program bin shorthand
  ip = "${pkgs.iproute}/bin/ip";
  nft = "${pkgs.nftables}/bin/nft";
  wg = "${pkgs.wireguard-tools}/bin/wg";
  nixosContainer = "${pkgs.nixos-container}/bin/nixos-container";

  # wgnet-NS service configures container namespace and starts wireguard
  # systemd.services."wgnet-${ns}" =
  mkWgNsService = cfg: let
    ns = cfg.name;
    configFile = valueOr cfg.configFile "/etc/router/${ns}/wg.conf"; # path to wireguard config
  in {
    description = "wireguard network in namespace ${ns}";
    wants = ["network-online.target" "nss-lookup.target"];
    requires = ["nftables.service"];
    after = ["network-online.target" "nss-lookup.target" "nftables.service"];
    wantedBy = ["multi-user.target"];
    path = with pkgs; [iproute nftables wireguard-tools];
    enable = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      ExecStart = let
        start = pkgs.writeShellScript "wgnet-${ns}-up" ''
          # create container namespace, veth bridge, and start wireguard
          set -x
          if [ ! -r "${configFile}" ]; then
            echo "wireguard config file missing: '${configFile}'"
            exit 10
          fi
          # create namespace
          ${ip} netns add ${ns}

          # create lo interface in ns
          ${ip} -n ${ns} addr add 127.0.0.1/8 dev lo
          ${ip} -n ${ns} link set lo up

          # create veth peer: ve-NS on host, and eth-lan-NS for namespace end.
          # The latter is created on the host then moved into the ns, and the -NS suffix removed.
          ${ip} link add ve-${ns} type veth peer name eth-lan-${ns} # create peers
          ${ip} link set eth-lan-${ns} netns ${ns}                  # move eth-lan-NS into ns
          ${ip} -n ${ns} link set dev eth-lan-${ns} name eth-lan    # rename without suffix inside ctr
          ${ip} addr add ${cfg.veHostIp4}/32 dev ve-${ns}           # set ip addr for host peer
          ${ip} -n ${ns} addr add ${cfg.veNsIp4}/32 dev eth-lan     # set ip addr for container peer
          ${ip} link set ve-${ns} up                                # start host peer
          ${ip} -n ${ns} link set eth-lan up                        # start container peer
          ${ip} route add ${cfg.veNsIp4}/32 dev ve-${ns} src ${cfg.veHostIp4} # route host to container peer
          ${ip} -n ${ns} route add ${cfg.veHostIp4}/32 dev eth-lan src ${cfg.veNsIp4} # route container to host peer

          # add nat rules on host - for forwarding host ports into container
          # __Note__: if these are re-enabled, don't forget to uncomment the related line in ExecStopPost
          #${nft} add table inet wgnat-${ns}
          #${nft} add chain inet wgnat-${ns} postrouting \{ type nat hook postrouting priority 100 \; policy accept \; \}
          #${nft} add rule  inet wgnat-${ns} postrouting handle 0 iifname ${cfg.lanIface} oifname ve-${ns} masquerade
          # chain for port forwarding and and rule to handle http in container
          #${nft} add chain inet wgnat-${ns} prerouting \{ type nat hook prerouting priority -100 \; policy accept \; \}
          #${nft} add rule  inet wgnat-${ns} prerouting handle 0 iifname ${cfg.lanIface} tcp dport http dnat ip to ${cfg.veNsIp4}

          # create wireguard connection (ipv4 only for now) and move into container as 'wg0'
          ${ip} link add wg-${ns} type wireguard
          ${ip} link set wg-${ns} netns ${ns}
          ${ip} -n ${ns} link set dev wg-${ns} name wg0
          ${ip} -n ${ns} addr add ${cfg.wgIp4} dev wg0
          ##${ip} -n ${ns} -6 addr add $IPV6 dev wg0
          ${ip} netns exec ${ns} ${wg} setconf wg0 "${configFile}"
          ${ip} -n ${ns} link set wg0 up
          # set default route in container through wireguard tunnel
          # this also routes dns lookups on 10.2.0.1
          ${ip} -n ${ns} route add default via ${cfg.wgIp4} dev wg0
          ##${ip} -n ${ns} -6 route add default dev wg0

          # initialize nftables in container namespace
          # Running this here instead of in container.networking.nftables
          # so that we don't need to give container cap NET_ADMIN.
          ${ip} netns exec ${ns} ${nft} -f - <<_NFT
            table inet wgnat-internal {
              chain output {
                # Drop everything by default.
                # No traffic allowed from container to lan, except established connections
                type filter hook output priority 100; policy drop;

                oif lo accept comment "Accept all packets sent to loopback"
                oifname "wg0" accept comment "Accept all packets that go out over Wireguard"
                ct state established,related accept comment "Accept all packets of established traffic"
              }

              chain input {
                # Drop everything by default
                type filter hook input priority -1; policy drop;
                ct state established,related accept
                iif lo accept
                iifname "eth-lan" accept comment "Accept all packets coming from lan (or host)"

                # this rule unused because we don't have any services available over wg tunnel
                #iifname "wg0" tcp dport { 1111, 2222 } accept comment "Accept specific ports coming from Wireguard"

                icmp type echo-request accept  # ping
                icmpv6 type != { nd-redirect, 139 } accept comment "Accept all ICMPv6 messages except redirects and node information queries (type 139).  See RFC 4890, section 4.4."

                iif != lo ip daddr 127.0.0.1/8 counter drop comment "drop connections to loopback not coming from loopback"
              }
            }
          _NFT
        '';
      in "${start}";
      ExecStopPost = let
        stop = pkgs.writeShellScript "wgnet-${ns}-down" ''
          # remove wg network and namespace
          set -x
          ${ip} netns exec ${ns} ${nft} delete table inet wgnat-internal
          # stop wireguard
          ${ip} -n ${ns} route del default dev wg0
          ##${ip} -n ${ns} -6 route del default dev wg0
          ${ip} -n ${ns} link del wg0
          # remove nat rules
          # __Note__: disabled becuase table creation is commented in ExecStart above
          ${nft} delete table inet wgnat-${ns} || true

          # remove veth peers and lo
          ${ip} -n ${ns} link del eth-lan
          ${ip} link del ve-${ns}
          ${ip} -n ${ns} link del lo
          # and finally the namespace
          ${ip} netns del ${ns}
        '';
      in "${stop}";
    }; # service config
  }; # service wgnet-NS

  mkContainerWrapper = cname: ns: {
    enable = true;
    description = "Run container ${cname} in net ns ${ns}";
    # delay starting container until vpn is up
    after = ["wgnet-${ns}.service"];
    # start vpn befure us, and stop us if vpn stops
    requires = ["wgnet-${ns}.service"];
    # if the vpn service disappears, this unit stops also
    bindsTo = ["wgnet-${ns}.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${nixosContainer} start ${cname}";
      ExecStopPost = "${nixosContainer} stop ${cname}";
    };
  };
in {
  systemd.services =
    # create a service for each vpn network namespace
    # systemd.services."wgnet-${ns}" = mkWgNsService cfg
    (listToAttrs
      (
        map (cfg: {
          name = "wgnet-${cfg.name}";
          value = mkWgNsService cfg;
        })
        (filter (cfg: cfg.enable) (attrValues config.my.vpnNamespaces))
      ))
    //
    # create service wrapper for each container with a namespace
    # The container sets autoStart=false because this wrapper controls starting and stopping
    # systemd.services."wgContainer-${cfg.ns}" = mkContainerWrapper cname ns;
    (listToAttrs
      (
        map
        (c: {
          name = "container-${c.name}-${c.namespace}";
          value = mkContainerWrapper c.name c.namespace;
        })
        (
          filter
          (c: (!isNull c.namespace) && config.my.vpnNamespaces.${c.namespace}.enable)
          (attrValues config.my.containers)
        )
      ));
}
