{
  pkgs,
  username,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  inherit (pkgs.lib) optionalAttrs;
in {
  imports = [
    ./git.nix
    ./helix.nix
    ./wezterm.nix
  ];

  # needed because home-manager is 24.11 and nixos is 24.05. I don't know why it's at 24.11 though
  home.enableNixpkgsReleaseCheck = false;

  home.username = username;
  home.homeDirectory =
    if isDarwin
    then "/Users/${username}"
    else "/home/${username}";
  home.stateVersion = "24.05";

  home.packages = with pkgs; [
    # nats
    nats-server
    natscli
    nsc
    nkeys
    pwgen
    jwt-cli
    step-cli # jwt/x509 utils

    # helix formatters & language servers
    alejandra
    gopls
    marksman
    nil
    shellcheck
    taplo

    # misc
    age
    bind.dnsutils
    aria2
    gnused
    gocryptfs
    nix-output-monitor
    nmap
    rclone
    restic
    rsync
    socat
    starship
    vault-bin
  ];

  # directories to add to PATH
  home.sessionPath = [
    "$HOME/bin"
  ];

  # example overrides
  # # It is sometimes useful to fine-tune packages, for example, by applying
  # # overrides. You can do that directly here, just don't forget the
  # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
  # # fonts?
  # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

  # # You can also create simple shell scripts directly inside your
  # # configuration. For example, this adds a command 'my-hello' to your
  # # environment:
  # (pkgs.writeShellScriptBin "my-hello" ''
  #   echo "Hello, ${config.home.username}!"
  # '')

  # files to link into home
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };

  programs.zsh = {
    enable = true;
    sessionVariables = rec {
      EDITOR = "${pkgs.helix}/bin/hx";
      VISUAL = EDITOR;
      TERM = "xterm-256color";
    };
    shellAliases =
      {
        gd = "git diff";
        gst = "git status";
        gpu = "git push -u origin";
        h = "hostname";
        j = "just";
        jwt-decode = "step crypto jwt inspect --insecure";
        wkeys = "wezterm show-keys --lua"; # wezterm key mapping
      }
      # mac-specific aliases
      // (optionalAttrs isDarwin {
        flushdns = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";
      });

    # doesn't work with "Apple_Terminal". Should we set COLORTERM for everything if not Apple_Terminal,
    initExtra = ''
      if [[ "$TERM_PROGRAM" != "Apple_Terminal" ]]; then
        export COLORTERM=truecolor
      fi
    '';
  };
}
