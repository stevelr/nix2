##
## This is not currently used - the actual seafile is an incus container
## with docker-compose.yml
##
{config, ...}: let
  netid = "seafileNet";
  seafileNet = config.my.subnets."seafileNet";
  staticIp = name: seafileNet.settings.seafile-A-records.${name};
  setNetwork = hostname: let
    ip = staticIp hostname;
  in [
    "--network=${netid}:ip=${ip}"
    "--dns=${seafileNet.dns}"
  ];
  autoStart = false;
  storePath = "/var/lib/seafile";
  dbPath = "/var/lib/db/mysql-seafile";
in {
  users.users.seafile = {
    isSystemUser = true;
    uid = config.const.userids.seafile.uid;
    group = "seafile";
  };
  users.groups.seafile = {
    gid = config.const.userids.seafile.gid;
  };
  virtualisation.oci-containers.containers = {
    ##
    ## seafile containerized by ggogel
    ##  https://github.com/ggogel/seafile-containerized
    ##

    seafile-server = rec {
      inherit autoStart;
      image = "ggogel/seafile-server:11.0.12";
      volumes = ["${storePath}/data:/shared"];
      hostname = "seafile-server";
      user = "seafile:seafile";
      environment = {
        DB_HOST = "seafile-db";
        DB_ROOT_PASSWD = "temporary-password"; # initial password only!!
        TIME_ZONE = config.my.containerCommon.timezone;
        HTTPS = "true";
        SEAFILE_URL = "seafile.pasilla.net";
      };
      dependsOn = ["seafile-db"];
      #restart = "unless-stopped";
      extraOptions =
        setNetwork hostname
        ++ [
          "--health-cmd=\"nc -z localhost 8082\""
          "--health-interval=10s"
          "--health-timeout=10s"
          "--health-retries=3"
        ];
    };

    seahub = rec {
      inherit autoStart;
      image = "ggogel/seahub:11.0.12";
      hostname = "seahub";
      user = "seafile:seafile";
      volumes = [
        "${storePath}/data:/shared"
        "${storePath}/avatars:/shared/seafile/seahub-data/avatars"
        "${storePath}/custom:/shared/seafile/seahub-data/custom"
      ];
      extraOptions = setNetwork hostname;
      environment = {
        SEAFILE_ADMIN_EMAIL = "admin@pangea";
        SEAFILE_ADMIN_PASSWORD = "temporary-password"; # changed after installation
      };
      dependsOn = ["seafile-db" "seafile-server"];
      #restart = "unless-stopped";
    };

    seafile-media = rec {
      inherit autoStart;
      image = "ggogel/seahub-media:11.0.12";
      hostname = "seafile-media";
      user = "seafile:seafile";
      volumes = [
        "${storePath}/avatars:/usr/share/caddy/media/avatars"
        "${storePath}/custom:/usr/share/caddy/media/custom"
      ];
      extraOptions = setNetwork hostname;
      #restart = "unless-stopped";
    };

    seafile-db = rec {
      inherit autoStart;
      image = "mariadb:10.11.9";
      hostname = "seafile-db";
      ports = ["127.0.0.1:1234:1234"];
      user = "seafile:seafile";
      environment = {
        MYSQL_ROOT_PASSWORD = "temporary-password"; # changed after installation
        MYSQL_LOG_CONSOLE = "true";
        MARIADB_AUTO_UPGRADE = "true";
      };
      volumes = [
        "${dbPath}:/var/lib/mysql"
      ];
      extraOptions =
        setNetwork hostname
        ++ [
          "--health-cmd=\"healthcheck.sh --su-mysql --connect --innodb_initialized\""
          "--health-interval=10s"
          "--health-timeout=10s"
          "--health-retries=3"
        ];
      #restart = "unless-stopped";
    };

    # memcached = rec {
    #   inherit autoStart;
    #   image = "memcached:1.6.29";
    #   hostname = "memcached";
    #   entrypoint = "memached -m 1024";
    #   extraOptions = setNetwork hostname;
    #   #restart = "unless-stopped";
    # };

    seafile-caddy = rec {
      inherit autoStart;
      image = "ggogel/seafile-caddy:2.8.4";
      hostname = "seafile-caddy";
      # point reverse proxy here
      ports = ["8000:80"];
      extraOptions = setNetwork hostname;
      #restart = "unless-stopped";
    };
  };
}
# for documentation for oc-container settings, see
# https://github.com/NixOS/nixpkgs/blob/e2dd4e18cc1c7314e24154331bae07df76eb582f/nixos/modules/virtualisation/oci-containers.nix

