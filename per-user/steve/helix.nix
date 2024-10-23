{pkgs, ...}: {
  programs.helix = {
    enable = true;
    package = pkgs.helix;

    defaultEditor = true;
    extraPackages = with pkgs; [
      alejandra # nix formatter
      bash-language-server
      docker-compose-language-service
      hclfmt
      lua-language-server
      marksman
      markdown-oxide
      nil # nix LSP
      #nixpkgs-fmt
      taplo
      taplo-lsp
      terraform-ls
      rust-analyzer
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
        bash-language-server.command = "${pkgs.bash-language-server}/bin/bash-language-server";
        nil = {
          command = "${pkgs.nil}/bin/nil";
          config = {
            nix.flake = {
              autoArchive = true;
              autoEvalInputs = true;
            };
          };
        };
        taplo.command = "${pkgs.taplo}/bin/taplo";
        terraform-ls.command = "${pkgs.terraform-ls}/bin/terraform-ls";
        vscode-css-language-server.command = "${pkgs.vscode-langservers-extracted}/bin/vscode-css-language-server";
        vscode-html-language-server.command = "${pkgs.vscode-langservers-extracted}/bin/vscode-html-language-server";
        vscode-json-language-server.command = "${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server";
        docker-compose-language-service.command = "${pkgs.docker-compose-language-service}/bin/docker-compose-langserver";
        lua-language-server.command = "${pkgs.lua-language-server}/bin/lua-language-server";
        marksman.command = "${pkgs.marksman}/bin/marksman";
        rust-analyzer.command = "${pkgs.rust-analyzer}/bin/rust-analyzer";
        markdown-oxide.command = "${pkgs.markdown-oxide}/bin/markdown-oxide";
        yaml-language-server.command = "${pkgs.yaml-language-server}/bin/yaml-language-server";
      };
      language = [
        {
          name = "bash";
          auto-format = true;
          language-servers = ["bash-language-server"];
        }
        {
          name = "markdown";
          language-servers = ["markdown-oxide"];
          formatter = {
            command = "prettier";
            args = ["--stdin-filepath" "file.md"];
          };
          auto-format = true;
        }
        {
          name = "lua";
          auto-format = true;
          language-servers = ["lua-language-server"];
        }
        {
          name = "nix";
          auto-format = true;
          formatter.command = "${pkgs.alejandra}/bin/alejandra";
          language-servers = ["nil"];
        }
        {
          name = "hcl";
          formatter.command = "${pkgs.hclfmt}/bin/hclfmt";
          language-servers = ["terraform-ls"];
        }
        {
          name = "json";
          language-servers = ["vscode-json-language-server"];
        }
        {
          name = "rust";
          language-servers = ["rust-analyzer"];
        }
        {
          name = "html";
          language-servers = ["vscode-html-language-server"];
        }
        {
          name = "css";
          language-servers = ["vscode-css-language-server"];
        }
        {
          name = "docker-compose";
          language-servers = ["docker-compose-language-service"];
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
