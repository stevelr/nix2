# per-user/steve/default.nix - home manager configuration
{pkgs, ...}: let
  inherit (pkgs.stdenv) isDarwin;
  inherit (pkgs.lib) optionalAttrs optionalString;
  inherit (builtins) filter concatStringsSep;

  username = "steve";
  homedir =
    if isDarwin
    then "/Users/${username}"
    else "/home/${username}";
  profileDir = "${homedir}/.nix-profile";
  #pathExists = p: ((p != "") && (builtins.pathExists p));
  # concatStringsSep ":" (filter pathExists [
  #"/nix/profile/bin"
in {
  imports = [
    ./git.nix
    ./helix.nix
    ./wezterm.nix
    ../../modules/cli.nix # tools for great cli experience
  ];

  home.username = username;
  home.homeDirectory = homedir;
  home.stateVersion = "24.05";
  # allow home-manager to be on unstable while nixos is on stable
  home.enableNixpkgsReleaseCheck = false;

  home.packages = with pkgs; [
    age
    #aria2
    fzf
    fzf-git-sh
    gh

    gocryptfs
    jwt-cli
    markdown-oxide # PKM
    natscli
    nix-output-monitor
    nmap
    pwgen
    socat
    step-cli # jwt/x509 utils
    vault-bin
  ];

  # directories to add to PATH
  home.sessionPath = [
    "${homedir}/bin"
    "${homedir}/.nix-profile/sbin"
    "${homedir}/.nix-profile/bin" # home profile directory
    "/etc/profiles/per-user/${username}/bin" # alt home profile directory
    "/run/wrappers/bin"
    "/run/current-system/sw/bin"
    (optionalString isDarwin "/opt/homebrew/bin")
    "${homedir}/.local/state/nix/profiles/profile/bin"
    "/etc/profiles/per-user/${username}/bin"
    "/nix/var/nix/profiles/default/bin"
    "/bin"
    "/usr/sbin"
    "/usr/bin"
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

  # aliases that work across shells. zsh-specific aliases should go in programs.zsh.shellAliases
  home.shellAliases =
    {
      gd = "git diff";
      gst = "git status";
      gpu = "git push -u origin";
      h = "hostname";
      j = "just";
      jwt-decode = "step crypto jwt inspect --insecure";
      msh = "sudo machinectl shell";
      wkeys = "wezterm show-keys --lua"; # wezterm key mapping
    }
    # mac-specific aliases
    // (optionalAttrs isDarwin {
      flushdns = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";
    });

  # added to hm-session-vars.sh
  home.sessionVariables = {
    EDITOR = "hx"; # "${pkgs.helix}/bin/hx";
    VISUAL = "hx";
    TERM = "xterm-256color";

    FZF_DEFAULT_COMMAND = "fd --hidden --strip-cwd-prefix --exclude .git";
    FZF_CTRL_T_COMMAND = "$FZF_DEFAULT_COMMAND";
    FZF_ALT_C_COMMAND = "fd --type=d --hidden --strip-cwd-prefix --exclude .git";
  };

  # Let Home Manager install and manage itself.
  #programs.home-manager.enable = true;

  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
    settings.editor = "hx";
    extensions = [
      pkgs.gh-f
    ];
  };

  programs.zsh = {
    enable = true;

    # zsh-specific aliases. Aliases that work across shells are defined in home.shellAliases
    shellAliases = {};

    initExtraFirst = ''
      # set PATH, EDITOR, and other variables
      source ~/.zshenv
    '';

    initExtra = ''
      # truecolor doesn't work with "Apple_Terminal", but everywhere else so far.
      if [[ "$TERM_PROGRAM" != "Apple_Terminal" ]]; then
        export COLORTERM=truecolor
      fi

      # initialize starship
      eval "$(starship init zsh)"

      # initialize fzf
      eval "$(fzf --zsh)"

      # Use fd (https://github.com/sharkdp/fd) for listing path candidates.
      # - The first argument to the function ($1) is the base path to start traversal
      # - See the source code (completion.{bash,zsh}) for the details.
      _fzf_compgen_path() {
        fd --hidden --exclude .git . "$1"
      }

      # Use fd to generate the list for directory completion
      _fzf_compgen_dir() {
        fd --type=d --hidden --exclude .git . "$1"
      }

      # fzf-git.sh
      source ${profileDir}/share/fzf-git-sh/fzf-git.sh

    '';
  };
}
