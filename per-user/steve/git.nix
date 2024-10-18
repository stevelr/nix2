{...}: {
  programs.git = {
    enable = true;
    userName = "stevelr";
    userEmail = "stevelr.git@pm.me";

    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      #credential.helper = "osxkeychain";
    };

    ignores = [
      ".direnv"
      "__pycache__"
      "node_modules"
      ".DS_Store"
    ];
  };
}
