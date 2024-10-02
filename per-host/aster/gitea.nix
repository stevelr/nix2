# gitea.nix
{
  config,
  pkgs,
  ...
}: let
  cfg = {
    sshPort = 3022;
    httpPort = 3000;
  };
in {
  containers.gitea = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";
    localAddress = "10.55.0.5/24";
    forwardPorts = [
      {
        hostPort = cfg.httpPort;
        containerPort = cfg.httpPort;
      }
      {
        hostPort = cfg.sshPort;
        containerPort = cfg.sshPort;
      }
    ];

    config = {
      environment.systemPackages = with pkgs; [
        helix
        jq
        nmap
        vim
      ];
      services.postgresql = {
        enable = true;
        #enableTCPIP = false; # false: only open unix domain socket
        package = pkgs.postgresql_16;
        dataDir = "/var/lib/pg-gitea";
        initdbArgs = ["--no-locale" "-E=UTF8" "-n" "-N"];
        ensureUsers = [{name = "gitea";}];
      };
      services.gitea = {
        enable = true;
        stateDir = "/var/lib/gitea";
        settings.server = {
          DOMAIN = "gitea";
          HTTP_PORT = cfg.httpPort;
          ROOT_URL = "http://10.55.0.5/";
          SSH_PORT = cfg.sshPort;
          SSH_LISTEN_PORT = cfg.sshPort;
          START_SSH_SERVER = true;
          PROTOCOL = "http";
        };
        database = {
          type = "postgres";
          # documentation is incorrect - this is a directory, not the actual file
          socket = "/run/postgresql";
          # name = "gitea";
          # createDatabase = true;
          # user = "gitea"
        };
      };

      environment.etc."resolv.conf".text = ''
        nameserver 10.135.1.1
      '';
      networking = {
        useDHCP = false;
        hostName = "aster-gitea";
        defaultGateway.address = "10.55.0.1";
        enableIPv6 = false;
        firewall.enable = false;
        #routes = [{Gateway = "10.55.0.1";}];
      };

      # force br0 nameserver
      services.resolved.enable = false;
      system.stateVersion = "24.05";
    }; # config
  }; # container gitea
}
