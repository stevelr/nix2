# connecting kea ddns to unbound
# thanks to codefionn https://codefionn.eu/ddns-with-unbound/
#
# codefionn's description:
#
# You might know that, kea also supports DDNS configuration. While that may be true,
#   this only works, if the DNS server supports TSIG. The problem is that unbound doesn't support it.
#   I looked into moving from unbound to a differnt DNS server (like Bind9 or Knot DNS),
#   but those are complicated to configure with NixOS, so I stayed with unbound.
# The solution: a bash script running as systemd service. The script itself requires that unbound
#   can be remote controlled and the inotify-tools for listening to file changes.

# This scripts reads the DHCP4/6-Leases CSV database stored by kea and then reads the address
#   and hostname from that table. unbound-control is called to set the A or AAAA record. If it is IPv4,
#   we reverse the IP-address and store a PTR record for reverse IP-lookup (dig -x YOUR.IP.GOES.HERE).
#   The wait at the end waits for the to forked syncFile-functions to finish.
# This script first reads all DHCP-leases and sets the DNS records accordingly and then waits
#   for changes in the DHCP-leases with inotify.
# Hostnames used for creating these DNS-Records must end here with your hostname + local-domain,
#   That's why, you have to make sure that your kea DHCPv4/6 has the following configuration option:
#
#   ddns-qualifying-suffix = "YOUR-HOSTNAME.lan"
#
# In your systemd-Service set PartOf, After and Wants to unbound.service. This will ensure that,
#   the script is started, after unbound and that the script is always restarted, when unbound
#    itself is. WantedBy must be set to multi-user.target.

{ config, pkgs, ... }:
let
  domainSuffix = config.my.localDomain;
in
{
  systemd.services.unbound-sync = {
    enable = true;
    path = with pkgs; [ unbound inotify-tools logger ipcalc ];
    script = ''
      function readFile() {
        if [[ "''\$2" == "A" ]] ; then
          cat "''\$1" | tail -n +2 | while IFS=, read -r address hwaddr client_id valid_lifetime expire subnet_id fqdn_fwd fqdn_rev hostname state user_context
          do
            echo "''\${address},''\${hostname}"
          done
        else
          cat "''\$1" | tail -n +2 | while IFS=, read -r address duid valid_lifetime expire subnet_id pref_lifetime lease_type iaid prefix_len fqdn_fwd fqdn_rev hostname hwaddr state user_context hwtype hwaddr_source
          do
            echo "''\${address},''\${hostname}"
          done
        fi
      }

      function readFileUnique() {
        readFile "''\$1" ''\$2 | uniq | while IFS=, read -r address hostname
        do
          if [[ "''\${hostname}" == *.${domainSuffix} ]] ; then
            logger -p local0.info --id=''\$''\$ forward ''\${hostname} ''\$2 ''\${address}
            unbound-control local_data ''\${hostname} ''\$2 ''\${address}
            if [[ "''\$2" == "A" ]] ; then
              reverse=''\$(ipcalc --reverse --no-decorate ''\${address})
              logger -p local0.info --id=''\$''\$ ip4 reverse ''\${reverse} ''\${hostname}
              unbound-control local_data ''\${reverse} PTR ''\${hostname}
            fi
          else
            logger -p local0.info --id=''\$''\$ skipping ''\${hostname} ''\$2 ''\${address}
          fi
        done
      }

      function syncFile() {
        if [ -r "''\$1" ]; then
          logger -p local0.info --id=''\$''\$ parsing leases in ''\$1
          readFileUnique "''\$1" "''\$2"
          while inotifywait -e close_write,create "''\$1" ; do
            readFileUnique "''\$1" "''\$2"
          done
        else
          logger -p local0.notice --id=''\$''\$ missing lease file ''\$1
        fi
      }

      syncFile "/var/lib/kea/dhcp4.leases" A &
      syncFile "/var/lib/kea/dhcp6.leases" AAAA &
      wait
    '';
    wants = [ "network-online.target" "unbound.service" ];
    after = [ "network-online.target" "unbound.service" ];
    partOf = [ "unbound.service" ];
    wantedBy = [ "multi-user.target" ];
  };
}
