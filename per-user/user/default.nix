# per-user/user/default.nix - home manager configuration
{pkgs, ...}: let
  inherit (pkgs.stdenv) isDarwin;
  inherit (pkgs.lib) optionalAttrs;
  username = "user";
in {
  home.username = username;
  home.homeDirectory =
    if isDarwin
    then "/Users/${username}"
    else "/home/${username}";
  home.stateVersion = "24.05";

  # allow home-manager to be on unstable while nixos is on stable
  home.enableNixpkgsReleaseCheck = false;

  home.packages = with pkgs; [
    bind.dnsutils
    starship
  ];

  # directories to add to PATH
  home.sessionPath = [
    "$HOME/bin"
  ];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

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
      }
      # mac-specific aliases
      // (optionalAttrs isDarwin {
        flushdns = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";
      });

    initExtra = ''
      if [[ "$TERM_PROGRAM" != "Apple_Terminal" ]]; then
        export COLORTERM=truecolor
      fi
    '';
  };
}
