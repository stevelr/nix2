# modules/cli.nix
# tools for a great cli experience - added to user's home-manager environment
{pkgs, ...}: {
  home.packages = with pkgs; [
    bat # better cat
    curl
    delta # git diff
    eza # better ls
    fd # fast find files
    file
    fzf # fuzzy finder
    git
    gnused
    jq
    just
    less
    ripgrep
    rsync
    shellcheck # syntax checker for bash
    starship
    tlrc # tldr client
    unzip
    xz # compress tools
    zoxide # better cd
  ];
}
