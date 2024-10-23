# handy tools
#  for network and system diagnostics
#
# To combine with system packages,
# append to another list like so:
#     ++ (import ./handy-tools.nix { inherit pkgs; }).full
#
# I haven't measured the size of the installation
#
{pkgs}: rec {
  minimal = with pkgs; [
    bind.dnsutils # dig
    curl
    git
    jq
    just
    less
    openssh
    ripgrep # fast recursive search in files
    rsync
    unzip
    vim
  ];

  nettools = with pkgs; [
    bandwhich # network utilization by process & connection
    bind.dnsutils # dig
    dhcpdump # tcpdump filtering for dhcp packets
    iperf # network bandwidth test
    mtr # network diagnostic
    #nftables # firewall tools
    nmap # net scanning and scripting
    sniffnet # monitor net traffic (web gui)
    speedtest-cli
    tcpdump
    trippy # network diagnostic (curses)
  ];

  full =
    minimal
    ++ nettools
    ++ (with pkgs; [
      age # encryption
      aria2 # torrent download
      fd # fast find files
      gnupg
      gnused # text editing scripted
      hck # hck (hack, like cut but with regex)
      helix
      htop
      lf # terminal file manager
      lsof # list open files/ports
      netcat
      pciutils # lspci
      pwgen # generate passwords
      rclone # sync files to various cloud backends
      restic # backups
      socat
      sqlite
      tldr # documentation
      wget
      xsv # csv processor
      xz # compression
    ]);

  tools = full;
}
