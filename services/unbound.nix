# unbound dns server
{ config, lib, ... }:
let
  inherit (builtins) isNull filter attrValues listToAttrs;
  #inherit (lib.attrsets) nameValuePair;

  lan0 = config.my.subnets."pangea-lan0";
  dnsNets = config.my.managedNets;
  # seafDomain = "${config.my.subnets.seafileNet.name}.${config.my.localDomain}";  # seaf0.<localDomain>

  # add domain to seafile hosts (append seaf0.<localDomain>)
  # seafZoneData =
  #   lib.attrsets.mapAttrs' (name: value: nameValuePair "${name}.${seafDomain}" value)
  #   config.my.subnets."seafileNet".settings.seafile-A-records;

  # for each container with static ip address, gen attribute { "fqdn" = "ipaddr" }
  containerStaticIps = listToAttrs (
      map (c: { name = "${c.name}.${config.my.subnets.${c.bridge}.domain}"; value = c.address; })
      ( filter ( n: ! (isNull n.address) ) (attrValues config.my.containers) )
  );

  # add an address so containers can easily access some services on the bridge ip
  # we'll also add this to the lan dns server but that will use pangea's external lan IP.
  vaultOnBridge = {
    "vault.pasilla.net" = config.my.subnets."pangea-br0".gateway;
    "seafile.pasilla.net" = config.my.subnets."pangea-br0".gateway;
  };
    #(lib.attrsets.mapAttrs' (name: cfg: nameValuePair
    #      "${cfg.name}.${config.my.subnets.${cfg.bridge}.domain}" cfg.address )

in
{
  services.unbound = {
    enable = true;

    # options https://github.com/NixOS/nixpkgs/blob/e2dd4e18cc1c7314e24154331bae07df76eb582f/nixos/modules/services/networking/unbound.nix

    settings = {
      server = {
        # listen interfaces
        interface = [
          "127.0.0.1"
          "::1"
        ] 
        ++ (map (n: n.gateway) dnsNets);
        port = 53;
        verbosity= 2; # 0=errors only; 1=operational (DEFAULT); 2=short info per query; 3=detail per query; 4=algorithm; 5=cache misses
        num-threads = 1; # One thread should be plenty
        # give access to clients on these netblocks
        access-control = [
          "127.0.0.1/8 allow"
        ] ++ (map (net: "${net.net} allow") dnsNets);
        #interface-action = [ "lo allow" "br0 allow" ];

        # allow this domain and its subdomains to contain private addresses
        private-domain= [
          "${config.my.localDomain}"
          lan0.domain
        ] ++ (map (net: net.domain) dnsNets);

        private-address = map (net: net.net) dnsNets;

        # these two are to try to get container lookups in br0 net to work
        unblock-lan-zones = false;
        insecure-lan-zones = true;

        # some pi-hole settings
        hide-identity = true;
        hide-version = true;

        # Based on recommended settings in https://docs.pi-hole.net/guides/dns/unbound/#configure-unbound
        harden-glue = true;
        harden-dnssec-stripped = true;
        use-caps-for-id = false;
        prefetch = true;
        edns-buffer-size = 1232;

        # create A records with all known static ip addresses
        # TODO: create reverse lookups too. Example:  "101.0.144.10.iin-addr.arpa. empty.br0.<localDomain>"
        local-data = lib.mapAttrsToList (n: v: "\"${n} A ${toString v}\"")
            (
              containerStaticIps
              // vaultOnBridge
              #// seafZoneData
            );
      };

      # open the remote control port for access from localhost.
      # This setting also adds a PreStart command (unbound-control-setup) to generate the keys
      remote-control.control-enable = true;

      forward-zone = [ {
          name = lan0.domain;
          forward-addr = lan0.dns;
      }]
      ++ (map (net: { name = net.domain; forward-addr = net.dns; }) dnsNets )
      ++ [{
          name = ".";
          forward-addr = lan0.dns;
      }]
      # ++ "9.9.9.9#dns.quad9.net"
      ;
    };
  };
}
