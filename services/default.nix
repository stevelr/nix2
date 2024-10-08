#
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (builtins) attrNames listToAttrs isNull;
  inherit (lib) mkOption mkEnableOption types;
  inherit (lib.attrsets) filterAttrs;

  valueOr = expr: other:
    if (! isNull expr)
    then expr
    else other;

  # extract first part of ip addr  "10.11.12.13" -> "10.11.12"
  first24 = addr: builtins.head (builtins.head (builtins.tail (builtins.split "([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+" addr)));

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

    # addressCIDR = mkOption {
    #   type = types.nullOr types.str;
    #   example = "10.10.10.82/24";
    #   default = null;
    #   description = "address in CIDR form. Defaults to <address>/<prefixLen>";
    # };

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
  };

  # fill in defaults from containerOptions
  # makeContainer = c: (lib.optionalAttrs c.enable {
  #   bridge = c.bridge;
  #   address = c.address;
  #   name = c.name;
  #   prefixLen = c.prefixLen;
  #   addressCIDR =
  #     if (! isNull c.address) && (isNull c.addressCIDR)
  #     then "${c.address}/${toString c.prefixLen}"
  #     else c.addressCIDR;
  #   proxyPort = c.proxyPort;
  #   settings = c.settings;
  #   enable = c.enable;
  # });

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
    dnsServers = valueOr n.dnsServers [dns];
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
    #./wgrouter.nix
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
        type = types.attrsOf (types.submodule {
          options = {
            port = mkOption {
              type = types.int;
              description = "listen port";
            };
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "whether the port should be opened";
            };
            description = mkOption {
              type = types.str;
              default = "";
              description = "description of port or service";
            };
          };
        });
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
        default = {enable = false;};
      };

      # initial data to be post-processed
      pre = {
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

      containerCommon = mkOption {
        type = types.submodule {
          options = {
            stateVersion = mkOption {
              type = types.str;
              description = "default nixos stateVersion for containers";
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

      service = mkOption {
        type = types.submodule {
          options = {
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
              default = {enable = false;};
              description = "tailscale client daemon options";
            };

            kea = mkOption {
              type = types.submodule {
                options = {
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
            };
          };
        };
      };
      # files = mkOption {
      #   type = types.attrs;
      # };
    }; # options.my
  };

  config = {
    # consistent id numbering for file mounts
    my.userids = {
      # interactive users
      steve = {
        uid = 1000;
        gid = 100;
        isInteractive = true;
      };
      user = {
        uid = 1001;
        gid = 100;
        isInteractive = true;
      };

      # services
      seafile = {
        uid = 4001;
        gid = 4001;
      };
      pmail = {
        uid = 4002;
        gid = 4002;
      };
      unbound = {
        uid = 4003;
        gid = 4003;
      };
      vault = {
        uid = 4004;
        gid = 4004;
      };
      gitea = {
        uid = 4005;
        gid = 4005;
      };
      postgres = {
        uid = 4006;
        gid = 4006;
      };
      nginx = {
        uid = 4007;
        gid = 4007;
      };

      grafana = {
        uid = 4010;
        gid = 4010;
      };
      prometheus = {
        uid = 4011;
        gid = 4011;
      };
      loki = {
        uid = 4012;
        gid = 4012;
      };
      tempo = {
        uid = 4013;
        gid = 4013;
      };
      nats = {
        uid = 4014;
        gid = 4014;
      };
      clickhouse = {
        uid = 4015;
        gid = 4015;
      };
      vector = {
        uid = 4016;
        gid = 4016;
      };
      #exporter = { uid = 4017; gid = 4017; }; # generic for node exporters

      # developer group
      developer = {gid = 4500;};
      # prometheus exporters
      exporters = {gid = 4501;};
    };

    # service ports
    my.ports = {
      clickhouseHttp = {port = 8123;};
      clickhouseTcp = {port = 9000;};
      incus = {port = 10200;};
      kea = {port = 14461;};
      nats = {port = 4222;};
      node = {
        port = 9100;
        description = "node exporter";
      };
      ssh = {port = 22;};
      tailscale = {port = 41641;}; # config.my.service.tailscale.port;
      unbound = {port = 53;};
      vault = {
        port = 8200;
        description = "Hashicorp vault api port";
      };
      vector = {port = 8686;};
      ##qryn = { port = 3100; };
    };

    my.containerCommon.timezone = "Etc/UTC";
    my.containerCommon.stateVersion = "24.05";

    my.subnets = builtins.mapAttrs (_: n: (makeNet n)) config.my.pre.subnets;
    my.hostNets = builtins.mapAttrs (_: n: (makeNet n)) config.my.pre.hostNets;
    # internal nets where we will run dhcp and dns servers
    my.managedNets = builtins.filter (n: n.dhcp.enable) (builtins.attrValues config.my.subnets);
  };
}
