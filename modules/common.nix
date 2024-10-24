{pkgs, ...}: {
  config = {
    environment.systemPackages = with pkgs; [
      bind.dnsutils
      curl
      fd
      file
      fzf
      git
      gnugrep
      gnupg
      gnused
      helix
      htop
      jq
      just
      less
      lsof
      netcat
      openssh
      openssl
      rclone
      restic
      ripgrep
      rsync
      unzip
      util-linux
      vim
      wget
      xz
    ];

    environment.variables = {
      VISUAL = "${pkgs.vim}/bin/vim";
      EDITOR = "${pkgs.vim}/bin/vim";
      PAGER = "${pkgs.less}/bin/less";
    };

    programs.bash.enable = true;
    programs.zsh.enable = true;
  };
}
