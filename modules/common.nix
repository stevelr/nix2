{pkgs, ...}: {
  lib.defaultLocale = "en_US.UTF-8";

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
}
