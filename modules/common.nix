{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    bind.dnsutils
    curl
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
    rclone
    restic
    ripgrep
    rsync
    unzip
    wget
    vim
    xz
  ];
}
