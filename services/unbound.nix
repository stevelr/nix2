# unbound dns server
{
  config,
  lib,
  ...
}: let
  inherit (builtins) isNull filter attrValues listToAttrs;
  #inherit (lib.attrsets) nameValuePair;
  cfg = config.my.services.unbound;

  lan0 = config.my.subnets.${cfg.wanNet};

  # dnsNets is the subnets for which we will provide DNS. Technically, it's subnets that have dhcp.enable=true,
  # but for now we provide dhcp (with Kea) and dns (with unbound) on the same nets
  dnsNets = config.my.managedNets;

  # seafDomain = "${config.my.subnets.seafileNet.name}.${config.my.localDomain}";  # seaf0.<localDomain>
  # add domain to seafile hosts (append seaf0.<localDomain>)
  # seafZoneData =
  #   lib.attrsets.mapAttrs' (name: value: nameValuePair "${name}.${seafDomain}" value)
  #   config.my.subnets."seafileNet".settings.seafile-A-records;

  # for each container with static ip address, gen attribute { "fqdn" = "ipaddr" }
  containerStaticIps = listToAttrs (
    map (c: {
      name = "${c.name}.${config.my.subnets.${c.bridge}.domain}";
      value = c.address;
    })
    (filter (n: ! (isNull n.address)) (attrValues config.my.containers))
  );
  # add an address so containers can easily access some services on the bridge ip
  # we'll also add this to the lan dns server but that will use pangea's external lan IP.
  # [ss]: this seems to be misnamed "vaultOnBridge" - is it really any service that should be mapped to gateway addr
  #   instead of its real IP in the container bridge net?
  # vaultOnBridge = lib.optionalAttrs (config.my.hostName == "pangea") {
  #   "vault.pasilla.net" = config.my.subnets."container-br0".gateway;
  #   "seafile.pasilla.net" = config.my.subnets."container-br0".gateway;
  # };
  # [ss] this looks like generation of dns mapping for containers. What's the relationship betw this and unbound-sync?
  # (does unbound-sync only work for new leases and not already-running containers?)
  # anyhow, where should this go?
  #(lib.attrsets.mapAttrs' (name: cfg: nameValuePair
  #      "${cfg.name}.${config.my.subnets.${cfg.bridge}.domain}" cfg.address )
in {
  services = lib.optionalAttrs cfg.enable {
    unbound = {
      enable = cfg.enable;

      # I'd like to use checkconf, but it has to be disabled when remote-control is enabled
      #  (ref: https://github.com/NixOS/nixpkgs/issues/293001)
      # and we need remote control for unbound-sync
      #checkconf = true; # check configuration for syntax errors

      # options https://github.com/NixOS/nixpkgs/blob/e2dd4e18cc1c7314e24154331bae07df76eb582f/nixos/modules/services/networking/unbound.nix

      settings = {
        server = {
          # listen interfaces
          interface =
            [
              "127.0.0.1"
              "::1"
            ]
            ++ (map (n: n.gateway) dnsNets);
          port = 53;
          # enable ipv4, ipv6, udp, and tcp
          do-ip4 = true;
          do-ip6 = true;
          do-udp = true;
          do-tcp = true;

          verbosity = 2; # 0=errors only; 1=operational (DEFAULT); 2=short info per query; 3=detail per query; 4=algorithm; 5=cache misses
          num-threads = 1; # One thread should be plenty
          # Ensure kernel buffer is large enough to not lose messages in traffic spikes
          so-rcvbuf = "1m";

          # give access to clients on these netblocks
          access-control =
            [
              "127.0.0.1/8 allow"
            ]
            ++ (map (net: "${net.net} allow") dnsNets);
          #interface-action = [ "lo allow" "br0 allow" ];

          # allow this domain and its subdomains to contain private addresses
          private-domain =
            [
              "${config.my.localDomain}"
              lan0.domain
            ]
            ++ (map (net: net.domain) dnsNets);

          private-address = map (net: net.net) dnsNets;

          # these two are to try to get container lookups in br0 net to work
          unblock-lan-zones = false;
          insecure-lan-zones = true;

          # some pi-hole settings
          hide-identity = true;
          hide-version = true;

          # Based on recommended settings in https://docs.pi-hole.net/guides/dns/unbound/#configure-unbound
          harden-glue = true;
          # Require DNSSEC data for trust-anchored zones, if such data is absent, the zone becomes BOGUS
          harden-dnssec-stripped = true;
          # Don't use Capitalization randomization as it known to cause DNSSEC issues sometimes
          # see https://discourse.pi-hole.net/t/unbound-stubby-or-dnscrypt-proxy/9378 for further details
          use-caps-for-id = false;
          prefetch = true;
          # Reduce EDNS reassembly buffer size.
          edns-buffer-size = 1232;

          # create A records with all known static ip addresses
          # TODO: create reverse lookups too. Example:  "101.0.144.10.iin-addr.arpa. empty.br0.<localDomain>"
          local-data =
            lib.mapAttrsToList (n: v: "\"${n} A ${toString v}\"")
            (
              containerStaticIps
              #              // vaultOnBridge
              #// seafZoneData
            );
        };

        # open the remote control port for access from localhost.
        # This setting also adds a PreStart command (unbound-control-setup) to generate the keys
        remote-control.control-enable = true;

        forward-zone =
          # forward lookup for "pasilla.net" if we're on pangea/lan
          lib.optionals (!isNull lan0.dns) [
            {
              name = lan0.domain;
              forward-addr = lan0.dns;
            }
          ]
          # add each subnet-domain with the dns server for that subnet
          # [ss] we are listening on these addresses. If we just have one unbound for all nets, we don't need this at all.
          #   I think this only makes sense if we have different unbound instances per subnet
          # ++ (map (net: {
          #     name = net.domain;
          #     forward-addr = net.dns;
          #   })
          #   dnsNets)
          ++ [
            {
              name = ".";
              # if we are connected to known lan net, use its dns. Otherwise (if roaming) fall back to known dns server
              # enable DNSSEC
              forward-addr =
                if (!isNull lan0.dns)
                then lan0.dns
                else [
                  "2620:fe::fe@853#dns.quad9.net"
                  "2620:fe::9@853#dns.quad9.net"
                  "9.9.9.9@853:dns.quad9.net"
                  "149.112.112.112@853#dns.quad9.net"
                ];
            }
          ];
      };
    };
  };
}
