{pkgs, ...}: {
  lib.defaultLocale = "en_US.UTF-8";

  networking.timeServers = [
    # using ip adddresses because for kea option-data.ntp-servers needs ip addresses.
    # TODO: figure out how to make it dynamic - perhaps at container boot time?
    "23.186.168.1"
    "72.14.183.39"
    "23.150.41.123"
    "23.150.40.242"
    "162.159.200.1"
    #"0.us.pool.ntp.org"
    #"1.us.pool.ntp.org"
    #"2.us.pool.ntp.org"
    #"3.us.pool.ntp.org"
  ];

  environment.systemPackages = with pkgs; [
    bind.dnsutils
    curl
    file
    git
    gnupg
    gnused
    helix
    htop
    jq
    just
    less
    netcat
    openssh
    openssl
    rclone
    restic
    ripgrep
    rsync
    unzip
    wget
    vim
    xz
  ];

  environment.variables = {
    VISUAL = "${pkgs.vim}/bin/vim";
    EDITOR = "${pkgs.vim}/bin/vim";
    PAGER = "${pkgs.less}/bin/less";
  };

  environment.homeBinInPath = true;
}
