{ config, pkgs, ... }:
let
  name = "vault";
  cfg = config.my.containers.${name};
  # api addr used during setup. external api uses other scripts
  localApiAddr = "http://127.0.0.1:${toString cfg.proxyPort}";
  bridgeCfg = config.my.subnets.${cfg.bridge};
  storagePath = "/var/lib/vault";
  inherit (pkgs) myLib;
  mkUsers = myLib.mkUsers config.my.userids;
  mkGroups = myLib.mkGroups config.my.userids;

in
{
  containers.${name} = {

    autoStart = cfg.enable;
    bindMounts = {
      "${storagePath}" = {
        hostPath = "/var/lib/vault";
        isReadOnly = false;
      };
    };
    privateNetwork = true;
    hostBridge = bridgeCfg.name;
    localAddress = "${cfg.address}/${toString bridgeCfg.prefixLen}";

    config = {

      environment.variables.TZ = config.my.containerCommon.timezone;
      environment.systemPackages = with pkgs; [
        vault-bin
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
        ui = true
        log_level = "${cfg.settings.logLevel}"
        listener "tcp" {
          address = "0.0.0.0:${toString cfg.proxyPort}"
          cluster_address = "0.0.0.0:${toString cfg.settings.clusterPort}"
          tls_disable = true
        }
        backend "raft" {
          path = "${storagePath}/data"
          node_id = "${cfg.bridge}"
        }
      '';
      users.users = (mkUsers [ "vault" ]);
      users.groups = (mkGroups [ "vault" ]);

      networking = myLib.netDefaults cfg bridgeCfg // {
        firewall.allowedTCPPorts = [
          cfg.proxyPort
          cfg.settings.clusterPort
        ];
      };

      services.resolved.enable = false; # force bridge nameserver

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
}
