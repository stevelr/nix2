# services/default.nix
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (builtins) isNull;
  inherit (lib) mkOption mkEnableOption types;
  inherit (pkgs.myLib) valueOr;

  # extract first three octets of ipv4 addr  "10.11.12.13" -> "10.11.12"
  first24 = addr: builtins.head (builtins.head (builtins.tail (builtins.split "([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+" addr)));

  # dhcpv4 pool x.x.x.100-x.x.x.199 (assumed to be within /24 subnet)
  defaultPool = addr: let
    prefix = first24 addr;
  in "${prefix}.100-${prefix}.199";

  containerOptions = {
    enable = mkOption {
      type = types.bool;
      example = true;
      description = ''
        whether the container should be enabled
      '';
      default = false;
    };

    bridge = mkOption {
      type = types.nullOr types.str;
      example = "br0";
      default = null;
      description = ''
        host bridge network and index into subnets config
      '';
    };

    address = mkOption {
      type = types.nullOr types.str;
      example = "10.100.0.43";
      default = null;
      description = ''
        Static ip of container on subnet.
        Do not use CIDR format: prefix will be obtained from the bridge's prefixLen.
        If the bridge has dhcp enabled, address can be null to use dhcp-assigned address.
      '';
    };

    name = mkOption {
      type = types.str;
      example = "pluto";
      description = ''
        Container name. also the host name for the container
      '';
    };

    prefixLen = mkOption {
      type = types.int;
      default = 24;
      description = ''
        prefix bits in network ip range
      '';
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      description = "other settings";
      default = {};
    };

    proxyPort = mkOption {
      type = types.int;
      default = 8000;
      description = ''
        primary exposed port - proxy target from nginx
      '';
    };

    namespace = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Network namespace, if container runs in vpn
      '';
    };
  };

  netOptions = {
    name = mkOption {
      type = types.str;
      example = "br0";
      description = ''
        name of host interface
      '';
    };

    localDev = mkOption {
      type = types.str;
      example = "eth0";
      default = "eth0";
      description = ''
        name of interface to the bridge
      '';
    };

    gateway = mkOption {
      type = types.nullOr types.str;
      example = "10.100.0.1";
      default = null;
      description = ''
        IP address of network gateway - for routing to WAN
      '';
    };

    net = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "10.100.0.0/24";
      description = ''
        IP address of the network in CIDR format
      '';
    };

    address = mkOption {
      type = types.nullOr types.str;
      example = "10.100.0.31";
      default = null;
      description = ''
        IP address in the network. Defaults to gateway
      '';
    };

    macAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "02:03:04:05:06:07";
      description = ''
        Mac address of local interface
      '';
    };

    prefixLen = mkOption {
      type = types.int;
      default = 24;
      example = 24;
      description = ''
        Number of bits in net prefix
      '';
    };

    dns = mkOption {
      type = types.nullOr types.str;
      example = "10.100.0.1";
      default = null;
      description = ''
        The primary dns server for this net. Defaults to gateway ip.
      '';
    };

    dnsServers = mkOption {
      type = types.nullOr (types.listOf types.str);
      example = ["10.100.0.1" "9.9.9.9"];
      default = null;
      description = ''
        DNS servers to set with dhcp. Only used if dhcp.enable is true.
        Defaults to [dns]
      '';
    };

    domain = mkOption {
      type = types.nullOr types.str;
      example = "example.com";
      default = null;
      description = ''
        dns domain. Defaults to <name>.<localDomain>
      '';
    };

    dhcp = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = ''
              true to enable dhcp for this net
            '';
          };
          pool = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              default pool for DHCP server
            '';
          };
          id = mkOption {
            type = types.int;
            default = -1;
            description = ''
              default pool for DHCP server
            '';
          };
          reservations = mkOption {
            type = types.listOf (types.submodule {
              options = {
                "hw-address" = mkOption {
                  type = types.str;
                  description = "MAC address";
                };
                "ip-address" = mkOption {
                  type = types.str;
                  description = "ip address";
                };
              };
            });
            default = [];
            description = "mapping from mac address to IP within the subnet";
          };
        };
      });
      default = {enable = false;};
      example = {
        enable = true;
        pool = "10.0.0.100-10.0.0.199";
        id = 7;
      };
      description = "dhcp server configuration";
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      description = "other settings";
      default = {};
    };
  };

  namespaceOptions = {
    enable = mkOption {
      type = types.bool;
      description = "enable the vpn namespace";
      default = true;
      example = false;
    };
    name = mkOption {
      type = types.str;
      example = "ns";
      description = "namespace name";
    };
    lanIface = mkOption {
      type = types.str;
      example = "enp2s0";
      description = "name of lan interface on host";
    };
    veNsIp4 = mkOption {
      type = types.str;
      example = "192.168.10.11";
      description = "ip addr of veth bridge in namespace";
    };
    veHostIp4 = mkOption {
      type = types.str;
      example = "192.168.10.10";
      description = "ip addr ofveth bridge on host";
    };
    wgIp4 = mkOption {
      type = types.str;
      default = "10.2.0.2";
      description = "client(local) ip addr in tunnel. For proton vpn, the default " 10.2 .0 .2 " should work";
    };
    wgGateway = mkOption {
      type = types.str;
      default = "10.2.0.1";
      description = "remote gateway in tunnel. For protonVPN, the default '10.2.0.1'should work";
    };
    vpnDns = mkOption {
      type = types.listOf types.str;
      example = ["10.2.0.1"];
      description = "dns servers for vpn clients";
    };
    configFile = mkOption {
      type = types.nullOr types.str;
      example = "/etc/wg/wg0.conf";
      description = "path to wireguard config file. Default is /etc/router/NAMESPACE/wg.conf";
      default = null;
    };
  };

  makeNet = n: let
    dns = valueOr n.dns n.gateway;
    hasDhcp = (! isNull n.dhcp) && n.dhcp.enable;
  in {
    name = n.name;
    localDev = n.localDev;
    gateway = n.gateway;
    prefixLen = n.prefixLen;
    macAddress = n.macAddress;
    address = valueOr n.address n.gateway;
    net = valueOr n.net "${first24 n.gateway}.0/${toString n.prefixLen}";
    inherit dns;
    dnsServers = valueOr n.dnsServers (
      # TODO: if dnsServers, dns, and gateway are all null, we don't have dns servers, so set to null here
      if (! isNull dns)
      then [dns]
      else null
    );
    domain = valueOr n.domain "${n.name}.${config.my.localDomain}";
    settings = n.settings;
    dhcp = {
      enable = hasDhcp;
      pool =
        if hasDhcp && (! isNull n.dhcp.pool)
        then n.dhcp.pool
        else defaultPool n.gateway;
      id =
        if hasDhcp && n.dhcp.id == -1
        then (pkgs.myLib.nethash n)
        else n.dhcp.id;
      reservations =
        if hasDhcp
        then n.dhcp.reservations
        else [];
    };
  };
in {
  imports = [
    ./const.nix
    ./gitea.nix
    ./clickhouse
    ./empty.nix
    ./empty-static.nix
    ./grafana.nix
    ./monitoring.nix
    ./nats.nix
    ./nettest.nix
    ./nginx.nix
    ./pmail.nix
    ./vault.nix
    ./unbound.nix
    ./unbound-sync.nix
    ./vpn-sh.nix
    ./wgrouter.nix
    ./media
  ];

  options = {
    my = {
      hostName = mkOption {
        type = types.str;
        description = "system hostname";
      };

      hostDomain = mkOption {
        type = types.str;
        description = "system domain";
      };

      localDomain = mkOption {
        type = types.str;
        example = "foo.com";
        description = "domain suffix for local internal networks. Should not be 'local' because that's reserved for mDNS";
      };

      enableIPv6 = mkOption {
        type = types.bool;
        default = true;
        description = "whether to enable IPv6 on LAN interfaces";
      };

      allowedUnfree = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "list of non-free packages to allow to be imported";
      };

      hardware.firmwareUpdates.enable = mkOption {
        type = types.bool;
        default = true;
        description = "enable irmware and microcode updates";
      };

      containers = mkOption {
        description = "configurations for containers";
        type = types.attrsOf (types.submodule {
          options = containerOptions;
        });
        default = {};
      };

      pre = {
        # initial data to be post-processed
        subnets = mkOption {
          type = types.attrsOf (types.submodule {
            options = netOptions;
          });
          default = {};
          description = "bridge networks connecting containers";
        };
        hostNets = mkOption {
          type = types.attrsOf (types.submodule {
            options = netOptions;
          });
          default = {};
          description = "host interfaces";
        };
      };

      subnets = mkOption {
        type = types.attrsOf (types.submodule {
          options = netOptions;
        });
        default = {};
        description = "bridge networks connecting containers";
      };

      hostNets = mkOption {
        type = types.attrsOf (types.submodule {
          options = netOptions;
        });
        default = {};
        description = "host interfaces";
      };

      managedNets = mkOption {
        type = types.listOf (types.submodule {
          options = netOptions;
        });
        default = {};
        description = ''
          (calculated value) list of virtual bridge nets on host where will run dns and dhcp servers
        '';
      };

      vpnNamespaces = mkOption {
        type = types.attrsOf (types.submodule {
          options = namespaceOptions;
        });
        default = {};
        description = "wireguard vpns";
      };

      containerCommon = mkOption {
        type = types.submodule {
          options = {
            stateVersion = mkOption {
              type = types.str;
              description = "default nixos stateVersion for containers";
              default = "24.05";
            };
            timezone = mkOption {
              type = types.str;
              default = "Etc/UTC";
              description = "timezone for containers";
            };
          };
        };
        description = "default options for containers.";
      };

      services = mkOption {
        type = types.submodule {
          options = {
            unbound = mkOption {
              type = types.submodule {
                options = {
                  enable = mkEnableOption "Unbound dns server";
                  wanNet = mkOption {
                    type = types.str;
                    description = "name of host wan/upstream network";
                    example = "host-lan0";
                  };
                };
              };
              default = {};
            };

            tailscale = mkOption {
              type = types.submodule {
                options = {
                  enable = mkEnableOption "Tailscale client daemon";
                  port = mkOption {
                    type = types.port;
                    default = config.const.ports.tailscale.port;
                    description = "port to listen on for tunnel traffic";
                  };
                };
              };
              default = {};
              description = "tailscale client daemon options";
            };

            kea = mkOption {
              type = types.submodule {
                options = {
                  enable = mkEnableOption "Kea DHCP";
                  control-agent = mkOption {
                    type = types.submodule {
                      options = {
                        enable = mkOption {
                          type = types.bool;
                          default = false;
                          example = true;
                          description = "enable kea control agent";
                        };
                        port = mkOption {
                          type = types.int;
                          default = config.const.ports.kea.port;
                          description = "http port for kea control agent";
                        };
                      };
                    };
                  };
                };
              };
              default = {};
            };

            prometheus = mkOption {
              type = types.submodule {
                options = {
                  enable = mkEnableOption "Prometheus";
                  net = mkOption {
                    type = types.nullOr types.str;
                    description = "name of network that prometheus uses";
                    exmaple = "br0";
                    default = null;
                  };
                };
              };
            };
          };
        };
        default = {};
      };
      # files = mkOption {
      #   type = types.attrs;
      # };
    }; # options.my
  };

  config = {
    # consistent id numbering for persistent direectories
    # and shared volume mounts
    my.containerCommon.timezone = "Etc/UTC";
    my.containerCommon.stateVersion = "24.05";

    my.subnets = builtins.mapAttrs (_: n: (makeNet n)) config.my.pre.subnets;
    my.hostNets = builtins.mapAttrs (_: n: (makeNet n)) config.my.pre.hostNets;
    # internal nets where we will run dhcp and dns servers
    my.managedNets = builtins.filter (n: n.dhcp.enable) (builtins.attrValues config.my.subnets);
  };
}
