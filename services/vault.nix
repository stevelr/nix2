{ config
, pkgs
, lib
, ...
}:
# Hashicorp vault
#   Initialization:
#   before running, create folder (on host) /var/lib/vault/data
#     and chown -R vault:vault /var/lib/vault
#   Then startup the container, enter container ('machinectl shell vault'), and run
#     'vault operator init' to get root key and unseal key
#   Put at least 3 unseal keys into /var/lib/vault/vault.env
#    using syntax "UNSEAL_KEY1=*******"
#   Save root token and unseal keys in 1password
#   TODO: work out interactive way to start vault with the unseal keys so they aren't on disk
let
  inherit (pkgs) myLib;
  inherit (lib) optionalString;

  name = "vault";
  cfg = myLib.configIf config.my.containers name;
  # api addr used during setup. external api uses apiAddr
  localApiAddr = "https://vault.aster.pasilla.net:${toString cfg.settings.apiPort}";
  bridgeCfg = config.my.subnets.${cfg.bridge};
  storagePath = "/var/lib/vault";
  mkUsers = myLib.mkUsers config.my.userids;
  mkGroups = myLib.mkGroups config.my.userids;
  # local paths for tls cert and private key
  tlsCertDir = "/etc/ssl/vault";
  tlsCertPath = "${tlsCertDir}/fullchain.pem";
  tlsKeyPath = "${tlsCertDir}/privkey.pem";
in
{
  containers = lib.optionalAttrs cfg.enable {
    vault = {
      autoStart = cfg.enable;
      bindMounts =
        {
          "${storagePath}" = {
            hostPath = "/var/lib/vault";
            isReadOnly = false;
          };
        }
        # add tls certs if vault is tls endpoint
        // (lib.optionalAttrs cfg.settings.tls.enable {
          "${tlsCertDir}/fullchain.pem" = { hostPath = cfg.settings.tls.chain; };
          "${tlsCertDir}/privkey.pem" = { hostPath = cfg.settings.tls.privkey; };
        });

      ephemeral = true;

      forwardPorts = [
        {
          hostPort = cfg.settings.apiPort;
          containerPort = cfg.settings.apiPort;
        }
        {
          hostPort = cfg.settings.clusterPort;
          containerPort = cfg.settings.clusterPort;
        }
      ];
      privateNetwork = true;
      hostBridge = bridgeCfg.name;
      localAddress = "${cfg.address}/${toString bridgeCfg.prefixLen}";

      config = {
        environment.variables.TZ = config.my.containerCommon.timezone;
        environment.systemPackages = with pkgs; [
          bind.dnsutils
          vault-bin
          lsof
          jq
        ];
        environment.etc."vault.d/vault.hcl".text = ''
          # address advertised to external clients for api use
          api_addr = "${cfg.settings.apiAddr}"
          cluster_name = "${cfg.settings.clusterName}"
          # full address advertised to cluster members
          cluster_addr = "${cfg.settings.clusterAddr}"
          disable_cache = true
          disable_mlock = true
          log_level = "${cfg.settings.logLevel}"
          ${optionalString cfg.settings.uiEnable "ui = true"}
          listener "tcp" {
            address = "0.0.0.0:${toString cfg.settings.apiPort}"
            cluster_address = "0.0.0.0:${toString cfg.settings.clusterPort}"
            ${optionalString cfg.settings.tls.enable ''
            tls_cert_file = "${tlsCertPath}"
            tls_key_file = "${tlsKeyPath}"
            tls_min_version = "tls13"
          ''}
            ${optionalString (!cfg.settings.tls.enable) ''
            tls_disable = true
          ''}
          }
          # after we switch to handling tls directly, instead of terminating at nginx, set tls_min_version
          # tls_min_version = "tls13"
          backend "raft" {
            path = "${storagePath}/data"
            node_id = "${cfg.bridge}"
          }
        '';
        users.users = mkUsers [ "vault" ];
        users.groups = mkGroups [ "vault" ];

        networking =
          myLib.netDefaults cfg bridgeCfg
          // {
            extraHosts = ''
              127.0.0.1 vault.aster.pasilla.net
            '';
            firewall.allowedTCPPorts = [
              cfg.settings.apiPort
              cfg.settings.clusterPort
            ];
          };

        services.resolved.enable = false; # force bridge nameserver

        # use stable mac address for dhcp consistency
        systemd.network.networks.eth0.dhcpV4Config.ClientIdentifier = "mac";

        systemd.services.vault = {
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          requires = [ "network-online.target" ];
          enable = cfg.enable;

          unitConfig = {
            Description = "Hashicorp Vault service";
            ConditionFileNotEmpty = "/etc/vault.d/vault.hcl";
            StartLimitIntervalSec = 60;
            StartLimitBurst = 3;
          };
          serviceConfig = {
            ExecStart = "${pkgs.vault-bin}/bin/vault server -config /etc/vault.d";
            ExecReload = "/run/current-system/sw/bin/kill --signal HUP $MAINPID";
            WorkingDirectory = storagePath;

            DynamicUser = false;
            User = "vault";
            Group = "vault";

            ProtectSystem = "full";
            PrivateTmp = "yes";
            PrivateDevices = "yes";
            SecureBits = "keep-caps";
            AmbientCapabilities = "CAP_IPC_LOCK";
            CapabilityBoundingSet = [ "CAP_SYSLOG" "CAP_IPC_LOCK" ];
            NoNewPrivileges = "yes";

            KillMode = "process";
            KillSignal = "SIGINT";

            Restart = "on-failure";
            RestartSec = "10s";
            TimeoutStopSec = "30s";

            LimitNOFILE = 65536;
            LimitMEMLOCK = "infinity";
            LimitCORE = "0";
            #Type="notify";
          };
        };

        # If we're in a container with dhcp we want to use this
        # but on the host we already know the lan ip addr
        # systemd.services.vault-addr = {
        #   wantedBy = [ "vault.service" ];
        #   before = [ "vault.service" ];
        #   enable = cfg.enable;

        #   serviceConfig = {
        #     Type = "oneshot";
        #     RemainAfterExit = true;
        #     Restart = "on-failure";
        #     RestartSec = "20s";
        #   };

        #   path = with pkgs; [ curl jq iproute2 ];

        #   script = ''
        #     set -exuo pipefail
        #     ip="$(ip -j addr | jq -r '.[] | select(.operstate == "UP") | .addr_info[] | select(.family == "inet") | .local')"
        #     addr="https://$ip"
        #     echo '{"cluster_addr": "'"$addr:${cfg.settings.clusterPort}"'", "api_addr": "'"$addr:${cfg.proxyPort}"'"}' \
        #     | jq -S . \
        #     > /etc/vault.d/address.json
        #   '';
        # };

        systemd.services.vault-unseal =
          let
            env-path = "${storagePath}/vault.env";
          in
          {
            wantedBy = [ "multi-user.target" ];
            partOf = [ "vault.service" ];
            after = [ "vault.service" ];
            path = with pkgs; [ curl jq ];
            enable = cfg.enable;
            serviceConfig = {
              User = "root";
              Group = "root";
            };
            script = ''
              set -a
              source "${env-path}"
              while true; do
                initialized=$(curl -s ${localApiAddr}/v1/sys/health | jq -r '.initialized')
                [[ "$initialized" = "true" ]] && break
                echo "Vault has not been initialized yet. Will try again after 5 seconds." >&2
                sleep 5
              done
              tee key1.json <<< "{ \"key\": \"$UNSEAL_KEY1\" }" >/dev/null
              tee key2.json <<< "{ \"key\": \"$UNSEAL_KEY2\" }" >/dev/null
              tee key3.json <<< "{ \"key\": \"$UNSEAL_KEY3\" }" >/dev/null
              curl -sS -X PUT --data @key1.json ${localApiAddr}/v1/sys/unseal | jq .
              curl -sS -X PUT --data @key2.json ${localApiAddr}/v1/sys/unseal | jq .
              curl -sS -X PUT --data @key3.json ${localApiAddr}/v1/sys/unseal | jq .
              shred -f -n 99 --remove -z key{1,2,3}.json
            '';
            serviceConfig.Type = "oneshot";
          };
        system.stateVersion = config.my.containerCommon.stateVersion;
      };
    };
  };
}
