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

      # allocate listening ports
      ports = mkOption {
        description = "listening ports";
        type = types.attrsOf types.anything;
        default = {};
      };

      userids = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            uid = mkOption {
              type = types.nullOr types.int;
              default = null;
              example = 1001;
              description = "user id";
            };
            gid = mkOption {
              type = types.nullOr types.int;
              default = null;
              example = 1001;
              description = "group id";
            };
            isInteractive = mkOption {
              type = types.bool;
              default = false;
              example = true;
              description = "true if the user logs in";
            };
            extraGroups = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              example = ["audio"];
              description = "optional list of additional groups for the user";
            };
            extraConfig = mkOption {
              type = types.nullOr (types.attrsOf types.anything);
              default = null;
              example = {packages = [pkgs.hello];};
              description = "additional user attributes";
            };
          };
        });
        description = "uid and gid settings for common users";
        default = {};
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
                    default = config.my.ports.tailscale.port;
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
                          default = config.my.ports.kea.port;
                          description = "http port for kea control agent";
                        };
                      };
                    };
                  };
                };
              };
              default = {};
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
    my.userids = {
      ##
      ## Interactive users
      ##
      steve =
        (
          if pkgs.stdenv.isDarwin
          then {
            uid = 501;
            gid = 20;
          }
          else {
            uid = 1000;
            gid = 100;
          }
        )
        // {
          isInteractive = true;
        };

      # generic user, usually low permission, for dev shells and misc containers
      user = {
        uid = 5500;
        gid = 100;
        isInteractive = true;
      };

      ##
      ## Service account ids starting at 5501 ...
      ## Group ids starting at 5801 ...
      ##
      # user ids 500-999 are available according to this ...
      # https://github.com/NixOS/nixpkgs/blob/f705ee21f6a18c10cff4679142d3d0dc95415daa/nixos/modules/programs/shadow.nix#L13-L14
      # .. however some unix services (sshd,ntpd,etc.) start at 998 counting down ..
      ##
      unbound = {
        uid = 5501;
        gid = 5501;
      };
      vault = {
        uid = 5502;
        gid = 5502;
      };
      gitea = {
        uid = 5503;
        gid = 5503;
      };
      postgres = {
        uid = 5504;
        gid = 5504;
      };
      mysql = {
        uid = 5505;
        gid = 5505;
      };
      clickhouse = {
        uid = 5506;
        gid = 5506;
      };
      seafile = {
        uid = 5507;
        gid = 5507;
      };
      nginx = {
        uid = 5508;
        gid = 5508;
      };
      grafana = {
        uid = 5509;
        gid = 5509;
      };
      prometheus = {
        uid = 5510;
        gid = 5510;
        extraGroups = ["exporters"];
      };
      loki = {
        uid = 5511;
        gid = 5511;
      };
      tempo = {
        uid = 5512;
        gid = 5512;
      };
      nats = {
        uid = 5513;
        gid = 5513;
      };
      vector = {
        uid = 5514;
        gid = 5514;
      };
      kea = {
        uid = 5515;
        gid = 5515;
      };
      pmail = {
        uid = 5516;
        gid = 5516;
      };
      # available: 5517-5549
      # skip a few
      media = {
        uid = 5550;
        gid = 5550;
        isInteractive = true;
        extraGroups = ["media-group"];
      };
      jellyfin = {
        uid = 5551;
        gid = 5551;
        extraGroups = ["media-group" "render" "video"];
      };
      sonarr = {
        uid = 5552;
        gid = 5552;
        extraGroups = ["media-group"];
      };
      radarr = {
        uid = 5553;
        gid = 5553;
        extraGroups = ["media-group"];
      };
      qbittorrent = {
        uid = 5554;
        gid = 5554;
        extraGroups = ["media-group"];
      };
      audiobookshelf = {
        uid = 5555;
        gid = 5555;
        extraGroups = ["media-group"];
      };
      jackett = {
        uid = 5556;
        gid = 5556;
        extraGroups = ["media-group"];
      };
      prowlarr = {
        uid = 5557;
        gid = 5557;
        extraGroups = ["media-group"];
      };

      ##
      ## Groups, starting at 5801
      ##
      # developer group
      developer = {gid = 5801;};
      # prometheus exporters
      exporters = {gid = 5802;};
      media-group = {gid = 5803;};
    };

    ##
    ## service ports
    ##
    my.ports = {
      clickhouse = {
        http = 8123; # http protocol
        binary = 9000; # binary protocol (TCP)
      };
      incus = {port = 10200;};
      kea = {port = 14461;};
      nats = {port = 4222;};
      node-exporter = {port = 9100;};
      ssh = {port = 22;};
      tailscale = {port = 41641;}; # config.my.services.tailscale.port;
      unbound = {port = 53;};
      vault = {
        apiPort = 8200;
        clusterPort = 8201;
      };

      vector = {port = 8686;};

      # media-group
      jellyfin = {port = 8096;};
      radarr = {port = 7878;};
      sonarr = {port = 8989;};
      prowlarr = {port = 9696;};
      #readarr = {port = 8787;};
      lidarr = {port = 8686;};
      bazarr = {port = 6767;};
      jackett = {port = 9117;};
      qbittorrent = {port = 11001;};
      audiobookshelf = {port = 7008;};
    };

    my.containerCommon.timezone = "Etc/UTC";
    my.containerCommon.stateVersion = "24.05";

    my.subnets = builtins.mapAttrs (_: n: (makeNet n)) config.my.pre.subnets;
    my.hostNets = builtins.mapAttrs (_: n: (makeNet n)) config.my.pre.hostNets;
    # internal nets where we will run dhcp and dns servers
    my.managedNets = builtins.filter (n: n.dhcp.enable) (builtins.attrValues config.my.subnets);
  };
}
