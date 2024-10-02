# Sub-modules that organize the more-involved details of my networking configuration.

{ config, pkgs, lib, ... }:
let
  machineId = "2f4d5023"; # first 8 chars of machine id
  iface1 = config.my.hostNets.hostlan1;
  iface2 = config.my.hostNets.hostlan2;
  dhcpNets = config.my.managedNets;
  toCsv = l: builtins.concatStringsSep "," l;
  useIpv6 = config.my.enableIPv6; # global ipv6 support

  # create network (systemd.network) from subnet info
  makeBridgeNet = net: {
    enable = true;
    matchConfig.Name = net.name;
    address = [ "${net.gateway}/${toString net.prefixLen}" ];
    networkConfig = {
      ConfigureWithoutCarrier = true;
    };
  };

  # create systemd.netdev from subnet info
  makeBridgeNetDev = net: {
    enable = true;
    netdevConfig = {
      Name = net.name;
      Kind = "bridge";
    };
  };

in
{
  imports = [
    ./firewall.nix
  ];

  # enable debug logging for network
  systemd.services."systemd-networkd".environment.SYSTEMD_LOG_LEVEL = "debug";

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv4.conf.all.rp_filter" = 0; # 0=off, 1=strict
  } // (lib.optionalAttrs useIpv6 {
    "net.ipv6.conf.all.forwarding" = true;
  });
  boot.initrd.systemd.network.enable = false;

  # no resolved or resolvconf
  services.resolved.enable = false;

  environment.etc."resolv.conf".text = ''
    search pasilla.net
    nameserver 127.0.0.1
    nameserver 10.135.1.1
  '';

  networking = {
    # enable/disable ipv6 on all interfaces
    enableIPv6 = useIpv6;
    
    hostName = config.my.hostName;
    domain = config.my.hostDomain;
    
    hostId = machineId; # required for zfs

    # install nftables but don't create a system-defined firewall
    firewall.enable = false;
    firewall.checkReversePath = false;
    nftables.enable = true;

    useNetworkd = true;

    resolvconf.enable = false;
    # if we do decide to use resolvconf, use systemd version not openresolv
    resolvconf.package = lib.mkForce pkgs.systemd;
  };

  # use systemd-networkd, rather than the legacy systemd.network 
  systemd.network.enable = true;

  systemd.network.networks = {

    "30-${iface1.localDev}" = {
      enable = true;
      name = iface1.localDev;
      DHCP = if useIpv6 then "yes" else "ipv4";
      matchConfig.Name = iface1.localDev;
      dhcpV4Config = { };
      networkConfig.IPv6AcceptRA = useIpv6;
    };

    "30-${iface2.localDev}" = {
      enable = true;
      name = iface2.localDev;
      DHCP = if useIpv6 then "yes" else "ipv4";
      matchConfig.Name = iface2.localDev;
      dhcpV4Config = {
        Hostname = "pangea2";
        UseHostname = false; # don't set hostname from dhcp response
      };
      networkConfig.IPv6AcceptRA = useIpv6;
    };
  }
  // builtins.listToAttrs (
    map
      (subnet: { name = "50-${subnet.name}"; value = makeBridgeNet subnet; })
      config.my.managedNets
  );

  systemd.network.links = {

    "10-${iface1.localDev}" = {
      enable = true;
      linkConfig.NamePolicy = "path";
      matchConfig = {
        Type = "ether";
        MACAddress = [ iface1.macAddress ];
      };
    };

    "10-${iface2.localDev}" = {
      enable = true;
      linkConfig = {
        NamePolicy = "path";
      };
      matchConfig = {
        Type = "ether";
        MACAddress = [ iface2.macAddress ];
      };
    };
  };

  systemd.network.netdevs = builtins.listToAttrs (
    map
      (subnet: { name = "20-${subnet.name}"; value = makeBridgeNetDev subnet; })
      config.my.managedNets
  );

  services.kea =
    let
      keaCtrlCfg = config.my.service.kea.control-agent;
      dhcp4Zone = snet: {
        id = snet.dhcp.id;
        interface = snet.name;
        subnet = "${snet.gateway}/${toString snet.prefixLen}";
        pools = [{ pool = snet.dhcp.pool; }];
        reservations = snet.dhcp.reservations;
        option-data = [
          {
            name = "domain-name";
            data = snet.domain;
          }
          {
            name = "domain-name-servers";
            data = toCsv snet.dnsServers;
          }
          {
            name = "domain-search";
            data = snet.domain;
          }

          {
            name = "routers";
            data = snet.gateway;
          }
          {
            name = "ntp-servers";
            data = toCsv config.networking.timeServers;
          }
        ];
        # DDNS is specific to this subnet (kea allows it to be set in global, shared-network, or subnet)
        #ddns-qualifying-suffix = "${containerDomain}";
        ddns-qualifying-suffix = snet.domain;
        comment = "containers on ${snet.name}";
      };
    in
    {
      ctrl-agent.enable = keaCtrlCfg.enable;
      ctrl-agent.settings = {
        "http-port" = keaCtrlCfg.port;
        "loggers" = [{
          name = "kea-ctrl-agent";
          severity = "INFO";
        }];
      };

      dhcp-ddns = {
        enable = true;
        settings = {
          ip-address = "127.0.0.1";
          port = 53001;
        };
      };

      dhcp4 = {
        enable = true;
        configFile = null;
        settings = {
          interfaces-config = {
            interfaces = map (n: n.name) dhcpNets;
          };
          valid-lifetime = 86400; # leases valid for 1 day
          renew-timer = 43200; # clients can renew after 12 hours
          lease-database = {
            type = "memfile";
            persist = true;
            name = "/var/lib/kea/dhcp4.leases";
          };
          loggers = [
            {
              name = "kea-dhcp4";
              output_options = [
                { output = "stdout"; }
              ];
              severity = "DEBUG";
            }
          ];
          subnet4 = map dhcp4Zone dhcpNets;
        };
      };
    };

  services.tailscale = 
  let
    cfg = config.my.service.tailscale;
  in {
    enable = cfg.enable;
    port = cfg.port;

    # authKeyFile = "/run/secrets/tailscale_key";
    extraUpFlags = [];
    extraSetFlags = [];
    extraDaemonFlags = [];
  };

    
}
