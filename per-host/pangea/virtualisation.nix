{ config, pkgs, ... }:
{
  config.virtualisation = {
    containers.enable = true;  # enable common /etc/containers configuration
    containers.containersConf.settings = {
      engine.compose_warning_logs = false;
      engine.compose_providers = [ "${pkgs.podman-compose}/bin/podman-compose" ];

      # unfortunately nftables still not supported yet:
      #   netavark needs to be v 0.10 or greater and it's still 0.7 as of 8--2024, even in nixos-unstable
      #network.firewall_driver = "nftables";
    };
    incus = 
    {
      enable = true; # cfg.enable;
      # preseed = {
      #   storage.backups_volume = "main-jwr9us/pangea/var/lib/incus-storage/backups";
      #   storage.images_volume = "main-jwr9us/pangea/var/lib/incus-storage/images";
      # };
    };
    lxc = {
      enable = false;
      lxcfs.enable = true;
    };


    # make podman the default container backend
    oci-containers.backend = "podman";

    podman = 
    let
      myPodman = config.my.subnets."pangea-podman0";
    in
    {
      enable = true;

      # enables systemd podman-prune.service to periodically prune podman resources
      autoPrune = {
        enable = true;
        dates = "weekly"; # when prune will occur: see systemd.time(7)
      };

      # create alias mapping docker to podman
      #dockerCompat = true; 

      # settings for default network
      # will be written to /etc/containers/networks/podman.json
      defaultNetwork.settings = {

        # so containers in a podman_compose can talk to each other
        dns_enabled = true;

        subnets = [
          {
            gateway = myPodman.gateway;
            subnet = myPodman.net;
          }
        ];
        network_interface = myPodman.name;
        # whether container uses ipv6. Requires host networking.enableIPv6
        ipv6_enabled = false; # default false
      }; # defaultNetwork.settings
    };

    #virtualbox = {
    #  host = {
    #    enable = mkDefault is.GUI;  # Note: Could be enabled when non-GUI, if desired.
    #    enableExtensionPack = mkDefault is.GUI;  # Note: Could be changed. Causes long rebuilds.
    #    headless = ! is.GUI;
    #  };
    #};

  };
}
