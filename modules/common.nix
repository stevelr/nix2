{pkgs, ...}: {
  config = {
    environment.systemPackages = with pkgs; [
      bind.dnsutils
      curl
      fd
      file
      fzf
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
      vim
      wget
      xz
    ];

    environment.variables = {
      VISUAL = "${pkgs.vim}/bin/vim";
      EDITOR = "${pkgs.vim}/bin/vim";
      PAGER = "${pkgs.less}/bin/less";
    };
  };
}
