# wgrouter.nix
# last updated 2024-07-07

# expects wireguard config file to be at /etc/router/${ns}/wg.conf
# where ns is the namespace name defined below

# currently supports ipv4 only
{ config, lib, pkgs, ... }:
let
  # All variables that define router are defined here. 
  # A single host can run multiple instances of this router container,
  # and the corresponding namespaced network,
  # as long as 'ns', 'veNsIp4', and 'veHostIp4' are unique on that host.
  lanIface = "enp2s0"; # lan interface of host
  ns = "ns101"; # unique namespace name
  wgIp4 = "10.2.0.2"; # local (vpn client) interface addr in wg tunnel
  vpnDns = [ "10.2.0.1" ]; # dns server(s) for vpn clients
  veNsIp4 = "192.168.10.11"; # name of veth bridge in namespace
  veHostIp4 = "192.168.10.10"; # name of veth bridge on host
  wgConf = "/etc/router/${ns}/wg.conf"; # wireguard config

  # program shorthand
  ip = "${pkgs.iproute}/bin/ip";
  nft = "${pkgs.nftables}/bin/nft";
  wg = "${pkgs.wireguard-tools}/bin/wg";
  nixosContainer = "${pkgs.nixos-container}/bin/nixos-container";
in
{
  # wgnet-NS service configures container namespace and starts wireguard
  systemd.services."wgnet-${ns}" = {
    description = "wireguard network in namespace ${ns}";
    wants = [ "network-online.target" "nss-lookup.target" ];
    requires = [ "nftables.service" ];
    after = [ "network-online.target" "nss-lookup.target" "nftables.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart =
        let
          start = pkgs.writeShellScript "wgnet-${ns}-up" ''
            # create container namespace, veth bridge, and start wireguard
            set -x

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
            ${ip} addr add ${veHostIp4}/32 dev ve-${ns}               # set ip addr for host peer
            ${ip} -n ${ns} addr add ${veNsIp4}/32 dev eth-lan         # set ip addr for container peer
            ${ip} link set ve-${ns} up                                # start host peer
            ${ip} -n ${ns} link set eth-lan up                        # start container peer
            ${ip} route add ${veNsIp4}/32 dev ve-${ns}                # route host to container peer
            ${ip} -n ${ns} route add ${veHostIp4}/32 dev eth-lan      # route container to host peer

            # add nat rules on host
            # __Note__: if these are re-enabled, don't forget to uncomment the related line in ExecStopPost
            #${nft} add table inet wgNat${ns}
            #${nft} add chain inet wgNat${ns} postrouting \{ type nat hook postrouting priority 100 \; policy accept \; \}
            #${nft} add rule  inet wgNat${ns} postrouting handle 0 iifname ${lanIface} oifname ve-${ns} masquerade
            # chain for port forwarding and and rule to handle http in container
            #${nft} add chain inet wgNat${ns} prerouting \{ type nat hook prerouting priority -100 \; policy accept \; \}
            #${nft} add rule  inet wgNat${ns} prerouting handle 0 iifname ${lanIface} tcp dport http dnat ip to ${veNsIp4}

            # create wireguard connection (ipv4 only for now) and move into container as 'wg0' 
            ${ip} link add wg-${ns} type wireguard
            ${ip} link set wg-${ns} netns ${ns}
            ${ip} -n ${ns} link set dev wg-${ns} name wg0
            ${ip} -n ${ns} addr add ${wgIp4} dev wg0
            ##${ip} -n ${ns} -6 addr add $IPV6 dev wg0
            ${ip} netns exec ${ns} ${wg} setconf wg0 ${wgConf}
            ${ip} -n ${ns} link set wg0 up
            # set default route in container through wireguard tunnel
            # this also routes dns lookups on 10.2.0.1
            ${ip} -n ${ns} route add default dev wg0
            ##${ip} -n ${ns} -6 route add default dev wg0

            # initialize nftables in container namespace
            # Running this here instead of in connector.networking.nftables
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
                  type filter hook input priority filter; policy drop;
      
                  iif lo accept
                  # enable ssh. This should be covered by the eth-lan rule below but this is a safeguard to prevent accidental blocks
                  tcp dport 22 accept
                  iifname "eth-lan" accept comment "Accept all packets coming from lan (or host)"
        
                  # this rule unused because we don't have any services available over wg tunnel
                  #iifname "wg0" tcp dport { 1111, 2222 } accept comment "Accept specific ports coming from Wireguard"
                  ct state established,related accept

                  iif != lo ip daddr 127.0.0.1/8 counter drop comment "drop connections to loopback not coming from loopback"
                }
              }
            _NFT
          '';
        in
        "${start}";
      ExecStopPost =
        let
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
            #${nft} delete table inet wgNat${ns} || true
            # remove veth peers and lo
            ${ip} -n ${ns} link del eth-lan
            ${ip} link del ve-${ns}
            ${ip} -n ${ns} link del lo
            # and finally the namespace
            ${ip} netns del ${ns}
          '';
        in
        "${stop}";
    }; # service config
  }; # service wgnet-NS

  systemd.services."wgcontainer-${ns}" = {
    description = "wireguard container";
    requires = [ "wgnet-${ns}.service" ];
    after = [ "wgnet-${ns}.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${nixosContainer} start wgcontainer-${ns}";
      ExecStopPost = "${nixosContainer} stop wgcontainer-${ns}";
    };
  };

  systemd.services."wgcontainer2-${ns}" = {
    description = "wireguard container2";
    requires = [ "wgnet-${ns}.service" ];
    after = [ "wgnet-${ns}.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${nixosContainer} start wgcontainer2-${ns}";
      ExecStopPost = "${nixosContainer} stop wgcontainer2-${ns}";
    };
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
  };

  containers."wgcontainer-${ns}" = {
    autoStart = false;
    # bind the network namespace to the container
    extraFlags = [ "--network-namespace-path=/run/netns/${ns}" ];
    config = { ... }:
      {
        system.stateVersion = config.my.containerCommon.stateVersion;
        #nixpkgs.config = { allowUnfree = true; };

        environment.systemPackages = with pkgs; [
          bash
          bind.dnsutils # includes dig
          curl
          fd
          git
          jq
          less
          lsof
          netcat
          ripgrep
          unzip
          vim
          wget
        ];
        environment.variables = rec {
          VISUAL = "${pkgs.vim}/bin/vim";
          EDITOR = VISUAL;
          COLORTERM = "truecolor";
          TERM = "xterm-256color";
          TZ = config.my.containerCommon.timezone;
        };
        users.users = {
          user = {
            isNormalUser = true;
            shell = pkgs.bash;
          };
        };
        environment.etc."resolv.conf".text =
          let
            # set dns resolver to the vpn's dns
            # set edns0 to enable extensions including DNSSEC
            nameServers = lib.strings.concatMapStringsSep
              "\n"
              (ip: "nameserver ${ip}")
              vpnDns;
          in
          ''
            option edns0
            ${nameServers}
          '';

        networking = {
          useHostResolvConf = lib.mkForce false;
          resolvconf.enable = false;
          nameservers = vpnDns;
          useNetworkd = true;
          firewall.enable = false;
          nftables.enable = true;
        }; # networking
      }; # config
  }; # container wgcontainer-NS

  # attempt to find out if two containers can bind to same network namespace
  containers."wgcontainer2-${ns}" = {
    autoStart = false;
    # bind the network namespace to the container
    extraFlags = [ "--network-namespace-path=/run/netns/${ns}" ];
    config = { ... }:
      {

        #nixpkgs.config = { allowUnfree = true; };

        environment.systemPackages = with pkgs; [
          bash
          bind.dnsutils # includes dig
          curl
          fd
          git
          jq
          less
          lsof
          netcat
          ripgrep
          unzip
          vim
          wget
        ];
        environment.variables = rec {
          VISUAL = "${pkgs.vim}/bin/vim";
          EDITOR = VISUAL;
          COLORTERM = "truecolor";
          TERM = "xterm-256color";
        };
        users.users = {
          user = {
            isNormalUser = true;
            shell = pkgs.bash;
          };
        };
        environment.etc."resolv.conf".text =
          let
            # set dns resolver to the vpn's dns
            # set edns0 to enable extensions including DNSSEC
            nameServers = lib.strings.concatMapStringsSep
              "\n"
              (ip: "nameserver ${ip}")
              vpnDns;
          in
          ''
            option edns0
            ${nameServers}
          '';
        networking = {
          useHostResolvConf = lib.mkForce false;
          nameservers = vpnDns;
          useNetworkd = true;
          firewall.enable = false;
          nftables.enable = true;
        }; # networking

        system.stateVersion = config.my.containerCommon.stateVersion;
      }; # config
  }; # containers
}
