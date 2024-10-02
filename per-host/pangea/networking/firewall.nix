{ config, lib, ... }:
let
  giteaCfg = config.my.containers.gitea; # gitea container cfg
  gitea_ip = giteaCfg.address; # gitea container on br0
  vaultCfg = config.my.containers.vault;
  vectorCfg = config.my.containers.vector;
  tsCfg = config.my.service.tailscale;
  clickhouseCfg = config.my.containers.clickhouse;
  nginx_ip = config.my.containers.nginx.address;
  bridges = config.my.managedNets; # list of internal bridges

  iface1 = config.my.hostNets.hostlan1;
  iface2 = config.my.hostNets.hostlan2;

  # out port for lan (forwarded nat from containers)
  lan_ip0 = iface1.address;
  lan_ip1 = iface2.address;
  any_lan_ip = "{ ${lan_ip0}, ${lan_ip1} }";

  # create nft set with all bridge names, eg "{ br0, seafnet0, appnet0 }"
  any_container_if = "{ " + (lib.concatStringsSep ", "
    (map (snet: snet.name) bridges)) + " }";

  # tcp services exposed on this host to lan
  # lan_tcp_services = "{ ${ssh}, ${https}, ${http}, ${vaultCls} }";

  # is the configured ip address one of the external LAN ip addresses?
  # isLanIp = ip: (ip == lan_ip0) || (ip == lan_ip1) || (ip == "0.0.0.0");

  ##
  ## Portsi for services on host.
  ##
  ## Use strings so they expand in rules below
  ssh = "22";
  dnsv4 = "53";
  http = "80";
  https = "443";
  mdns = "5353";
  chHttp = toString clickhouseCfg.settings.httpPort;
  chTcp= toString clickhouseCfg.settings.tcpPort;
  vectorApi = toString vectorCfg.settings.apiPort;
  exporters = "{ 9100-9799 }";
  #exporters = toString config.services.prometheus.exporters.systemd.port;
  tailscalePort = toString tsCfg.port;
  dhcp_ports = "{ 67, 68 }";
  vaultCls = toString vaultCfg.settings.clusterPort;
  gitea_pub_ssh = toString giteaCfg.settings.hostSsh;
  gitea_int_ssh = toString giteaCfg.settings.ssh;

  # DNAT ports forwarded to containers
  forwardedPorts = "{ ${http}, ${https}, ${gitea_pub_ssh}, ${vaultCls}, ${chHttp}, ${chTcp}, ${vectorApi} }";
   
  # use this to comment out rules pertaining to ipv6 if ipv6 is disabled
  ifv6 = if config.my.enableIPv6 then "" else "# ";

  ##
  ## rule generation
  ##

  ## If tailscale service is enabled, enable the udp port in
  # I don't know if this is necessaf
  acceptTailscale = if tsCfg.enable then ''
    udp dport ${tailscalePort} accept
  '' else "";
  
  # counters for bridge nat traffic
  bridge_nat_counters = lib.concatStringsSep "\n"
    (map
      (snet: ''
        counter ctr_nat_${snet.name} { comment "nat from ${snet.name} to host or lan" }
      '')
      bridges);

  bridge_SNAT_out = lib.concatStringsSep "\n"
    (map
      (snet:
        "iifname ${snet.name} ip saddr ${snet.net} ip daddr != ${snet.net} counter name ctr_nat_${snet.name} masquerade"
      )
      bridges);

  # lan access to https and dns incus admin
  # incus_allow_if = enabled:
  #   if enabled then
  #     (
  #       # since the incus_lan_rules are added to the input-lan-allow chain, it only makes sense if the https and dns listen
  #       # ip addresses are lan ip addresses (or listen all 0.0.0.0). If either https or dns is moved to a different ip
  #       # such as 127.0.0.1 or an internal bridge, the rules need to be put into a different chain
  #       # These assertions will let us know if https or dns address changed and we forgot to update firewall rules accordingly
  #       # Assertion checks only run if incus is enabled.
  #       assert isLanIp incusCfg.https.ip; # "incus https ip is expected to be an external lan address"
  #       assert isLanIp incusCfg.dns.ip;   # "incus https ip is expected to be an external lan address"
  #       (
  #         if incusCfg.https.ip == "0.0.0.0" then ''
  #           tcp dport ${toString incusCfg.https.port} accept comment "incus https admin"
  #         '' else ''
  #           ip daddr ${incusCfg.https.ip} tcp dport ${toString incusCfg.https.port} accept comment "incus https admin"
  #         ''
  #       ) + (
  #         if incusCfg.dns.ip == "0.0.0.0" then ''
  #           tcp dport ${toString incusCfg.dns.port} accept comment "incus internal dns"
  #         '' else ''
  #           ip daddr ${incusCfg.dns.ip} tcp dport ${toString incusCfg.dns.port} accept comment "incus internal dns"
  #         ''
  #       )
  #     ) else "";
  # incus_lan_rules = incus_allow_if incusCfg.enable;
  incus_lan_rules = "";

  ##
  ## NFTABLES hooks
  ##
  ##  IP
  ## ============
  ## -450             raw before defrag
  ## -400             defragmentation
  ## -300 raw         raw table before conntrack
  ## -225             SELinux operations
  ## -200             conntrack
  ## -150 mangle
  ## -100 dstnat      (DNAT)
  ##    0 filter
  ##   50 security    (set setmark)
  ##  100 srcnat      (SNAT)
  ##  225             SELinux at packet exit
  ##  300             conntrack helpers
  ##   
  ##
  ## BRIDGE
  ## ============
  ##
  ##  -300 dstnat
  ##  -200 filter
  ##     -
  ##   100 out
  ##   200
  ##   300 srcnat
  ##
in
{
  # Host nftables firewall
  # container firewalls are in their own namespace and are defined elsewhere
  # we can't flushRuleset prior to load,
  # because systemd-nspawn creates tables (ip io.systemd.nat && ip6 io.systemd.nat) for forwarding to containers

  config = {
    networking.nftables.enable = true;
    networking.nftables.checkRuleset = true;
    networking.nftables.tables = {
      host = {
        family = "inet";
        content = ''
          counter input_refused       { comment "input refused" }
          counter input_nomatch       { comment "input no match" }
          counter input_allow_nomatch { comment "input-allow no match" }
          counter input_ctr_nomatch   { comment "input-container no match" }
          counter lan_http            { comment "input-lan http" }
          counter lan_https           { comment "input-lan https" }
          counter lan_ssh             { comment "input-lan ssh to pangea" }
          counter lan_vault_api       { comment "input-lan vault api" }
          counter lan_vault_cluster   { comment "input-lan vault cluster" }
          counter lan_nomatch         { comment "input-lan no match" }
          counter input_forward       { comment "inet input forwarded ports" }
          counter ctr_http            { comment "input-ctr http" }
          counter ctr_https           { comment "input-ctr https" }
          counter ctr_ssh             { comment "input-ctr ssh" }
          counter ctr_vault_api       { comment "input-ctr vault api" }
          counter ctr_vault_cluster   { comment "input-ctr vault cluster" }

        	chain input {
        		type filter hook input priority filter;              policy drop;
        		iif "lo"                                             accept comment "allow from loopback"
        		ct state vmap { \
                invalid : drop, \
                established : accept, \
                related : accept, \
                new : jump input-allow, \
                untracked : jump input-allow \
            }
            # any forwardPorts defined in nspawn containers are forwarded by dnat rules
            # in tables (ip io.systemd.nat) and (ip6 io.systemd.nat) created by systemd.
            # Those ports need to be accepted here at priority 0.
            tcp dport ${forwardedPorts} \
                counter name input_forward                        accept

        		tcp flags syn / fin,syn,rst,ack \
                 log prefix "refused connection: " level info \
                 counter name input_refused
            counter name input_nomatch #                          drop
        	}

        	chain input-allow {
            # lockout prevention: allow ssh from anywhere - even if interface names change
            tcp dport ${ssh} counter name lan_ssh                accept
            # dhcp, all interfaces
            udp dport ${dhcp_ports}                              accept
            # This icmp rule may be too loose, but ok for trusted lan and containers
            ip protocol 1                                        accept comment "allow icmp"
            ${ifv6} meta l4proto 58                              accept comment "allow icmpv6"
            ip daddr ${any_lan_ip}                               jump input-lan-allow
            iifname ${any_container_if}                          jump input-container-allow
            ${acceptTailscale}
            counter name input_allow_nomatch #                    drop
        	}

          chain input-lan-allow {
            # Acccept TCP LAN services
            tcp dport ${ssh}      counter name lan_ssh           accept 
            # lxd container admin
            ${incus_lan_rules}

            # TODO: tighten this up by restricting source ip or enumerating ports
            tcp dport ${exporters}                               accept

            # udp: traceroute
        		udp dport { 33434-33524 }                            accept
            counter name lan_nomatch                             drop
          }

          chain input-container-allow {
            # Acccept TCP services from containers
            tcp dport ${https}    counter name ctr_https         accept 
            tcp dport ${http}     counter name ctr_http          accept 
            tcp dport ${ssh}      counter name ctr_ssh           accept 

            # tcp: dns
            tcp dport ${dnsv4}                                   accept

            # udp: dns, dhcp, traceroute
            udp dport { ${dnsv4}, 67-68, 33434-33524 }           accept

            # mdns from containers
            ip daddr "224.0.0.251"  udp dport ${mdns}            accept comment mdns
            ${ifv6} ip6 daddr "ff02::fb"  udp dport ${mdns}      accept comment mdns
        		${ifv6} ip6 daddr fe80::/64   udp dport 546          accept comment DHCPv6 
            counter name input_ctr_nomatch                       drop
          }

          # Default policy is accept so this chain isn't required if empty.
          # But I want it here so I can add logging rules
          # chain output {
        	# type filter hook output priority 0;                  policy accept;
          # }
        '';
      };

      # container-nat has snat rules for traffic from containers to LAN/WAN
      # dnat rules for forwarding ports into containers are generated by nixos nspawn
      # There aren't quite enough hooks in the nixos-container/systemd-nspawn wrappers
      # to overwrite those. We just make sure that they are in different tables,
      # and any ports that are forwarded are accepted in the input rules above. 
      "container-nat" = {
        family = "ip";
        content = ''
          counter ctr_nat_v4    { comment "container nat ipv4 pre" }
          counter ctr_gitea_ssh { comment "gitea ssh nat" }
          counter ctr_nomatch   { comment "container no match" }
          counter nat_post      { comment "nat postrouting" }
          counter nat_post_miss { comment "nat postrouting no masq" }
          ${bridge_nat_counters}

          chain post {
            # priority 100
          	type nat hook postrouting priority srcnat; policy accept;
          
            # source nat from containers out through primary lan interface
            ${bridge_SNAT_out}
          }
        '';
      };

      "container-nat-v6" = {
        family = "ip6";
        enable = config.my.enableIPv6;
        content = ''
          counter ctr_nat_v6   { comment "container nat ipv6 pre" }
          chain pre {
          	type nat hook prerouting priority dstnat; policy accept;
            counter name ctr_nat_v6
          }
          chain post {
          	type nat hook postrouting priority srcnat; policy accept;
          }
        '';
      };
    };
  };
}
