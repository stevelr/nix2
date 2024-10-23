{pkgs, ...}: {
  programs.helix = {
    enable = true;
    package = pkgs.helix;

    defaultEditor = true;
    extraPackages = with pkgs; [
      #bash-language-server
      alejandra # nix formatter
      docker-compose-language-service
      marksman
      nil # nix LSP
      #nixpkgs-fmt
      taplo
      taplo-lsp
      vscode-langservers-extracted
      yaml-language-server
    ];

    settings = {
      theme = "gruvbox";
      editor = {
        color-modes = true;
        line-number = "relative";
        cursorline = true; # highlight all lines with a cursor
        bufferline = "multiple"; # only show buffers at top when there are multiple buffers
        soft-wrap.enable = true;

        cursor-shape = {
          insert = "bar";
          normal = "block";
          select = "underline";
        };

        file-picker = {
          hidden = false;
          ignore = true;
        };

        lsp = {
          display-inlay-hints = true;
          display-messages = true;
        };

        statusline = {
          left = ["mode" "file-name" "spinner" "read-only-indicator" "file-modification-indicator"];
          right = ["diagnostics" "selections" "register" "file-type" "file-line-ending" "position"];
          mode.normal = "";
          #mode.insert = "I";
          mode.select = "S";
        };
      };
    };

    languages = {
      language-server = {
        nil = {
          command = "${pkgs.nil}/bin/nil";
          config = {
            nix.flake = {
              autoArchive = true;
              autoEvalInputs = true;
            };
          };
        };
      };
      language = [
        {
          name = "markdown";
          language-servers = ["marksman"];
          formatter = {
            command = "prettier";
            args = ["--stdin-filepath" "file.md"];
          };
          auto-format = true;
        }
        {
          name = "nix";
          auto-format = true;
          formatter.command = "${pkgs.alejandra}/bin/alejandra";
          language-servers = ["nil"];
        }
        {
          name = "toml";
          language-servers = ["taplo"];
          formatter = {
            command = "${pkgs.taplo}/bin/taplo";
            args = ["fmt" "-o" "column_width=120" "-"];
          };
          auto-format = true;
        }
        {
          name = "yaml";
          language-servers = ["yaml-language-server"];
          formatter = {
            command = "prettier";
            args = ["--stdin-filepath" "file.yaml"];
          };
          auto-format = true;
        }
      ];
    };
  };
}
