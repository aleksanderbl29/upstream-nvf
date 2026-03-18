{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (builtins) attrNames elem;
  inherit (lib.options) mkEnableOption mkOption literalExpression;
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.types) enum;
  inherit (lib.meta) getExe;
  inherit (lib.nvim.types) mkGrammarOption deprecatedSingleOrListOf;
  inherit (lib.nvim.attrsets) mapListToAttrs;
  inherit (lib.generators) mkLuaInline;

  cfg = config.vim.languages.r;

  r-with-languageserver = pkgs.rWrapper.override {
    packages = [pkgs.rPackages.languageserver];
  };

  defaultFormat = ["format_r"];
  formats = {
    air = {
      command = getExe pkgs.air-formatter;
      args = ["format" "$FILENAME"];
      stdin = false;
    };

    styler = {
      command = let
        pkg = pkgs.rWrapper.override {packages = [pkgs.rPackages.styler];};
      in "${pkg}/bin/R";
      args = ["-s" "-e" "styler::style_file(commandArgs(TRUE))" "--args" "$FILENAME"];
      stdin = false;
    };

    format_r = {
      command = let
        pkg = pkgs.rWrapper.override {
          packages = [pkgs.rPackages.formatR];
        };
      in "${pkg}/bin/R";
      stdin = true;
      args = [
        "--slave"
        "--no-restore"
        "--no-save"
        "-s"
        "-e"
        ''formatR::tidy_source(source="stdin")''
      ];
      # TODO: range_args seem to be possible
      # https://github.com/nvimtools/none-ls.nvim/blob/main/lua/null-ls/builtins/formatting/format_r.lua
    };
  };

  defaultServers = ["r_language_server"];
  servers = {
    air = {
      enable = true;
      cmd = [(getExe pkgs.air-formatter) "server"];
      filetypes = ["r" "rmd" "quarto"];
      root_markers = ["DESCRIPTION" ".air.toml" "renv.lock" ".git"];
    };

    r_language_server = {
      enable = true;
      cmd = [(getExe r-with-languageserver) "--no-echo" "-e" "languageserver::run()"];
      filetypes = ["r" "rmd" "quarto"];
      root_dir = mkLuaInline ''
        function(bufnr, on_dir)
          on_dir(vim.fs.root(bufnr, '.git') or vim.uv.os_homedir())
        end
      '';
    };
  };
in {
  options.vim.languages.r = {
    enable = mkEnableOption "R language support";

    treesitter = {
      enable =
        mkEnableOption "R treesitter"
        // {
          default = config.vim.languages.enableTreesitter;
          defaultText = literalExpression "config.vim.languages.enableTreesitter";
        };
      package = mkGrammarOption pkgs "r";
    };

    lsp = {
      enable =
        mkEnableOption "R LSP support"
        // {
          default = config.vim.lsp.enable;
          defaultText = literalExpression "config.vim.lsp.enable";
        };

      servers = mkOption {
        type = deprecatedSingleOrListOf "vim.language.r.lsp.servers" (enum (attrNames servers));
        default = defaultServers;
        description = "R LSP server to use";
      };
    };

    format = {
      enable =
        mkEnableOption "R formatting"
        // {
          default = config.vim.languages.enableFormat;
          defaultText = literalExpression "config.vim.languages.enableFormat";
        };

      type = mkOption {
        type = deprecatedSingleOrListOf "vim.language.r.format.type" (enum (attrNames formats));
        default = defaultFormat;
        description = "R formatter to use";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.treesitter.enable {
      vim.treesitter.enable = true;
      vim.treesitter.grammars = [cfg.treesitter.package];
    })

    (mkIf cfg.format.enable {
      vim.formatter.conform-nvim = {
        enable = true;
        setupOpts = {
          formatters_by_ft.r = builtins.filter (
            name: !(name == "air" && elem "air" cfg.lsp.servers)
          ) cfg.format.type;
          formatters =
            mapListToAttrs (name: {
              inherit name;
              value = formats.${name};
            })
            cfg.format.type;
        };
      };
    })

    (mkIf cfg.lsp.enable {
      vim.lsp.servers =
        mapListToAttrs (n: {
          name = n;
          value =
            if n == "r_language_server" && elem "air" cfg.lsp.servers
            then
              servers.${n}
              // {
                on_attach = mkLuaInline ''
                  function(client, _)
                    client.server_capabilities.documentFormattingProvider = false
                    client.server_capabilities.documentRangeFormattingProvider = false
                  end
                '';
              }
            else servers.${n};
        })
        cfg.lsp.servers;

      vim.formatter.conform-nvim = mkIf (elem "air" cfg.lsp.servers) {
        enable = true;
        setupOpts.formatters_by_ft = {
          quarto = ["injected"];
          rmd = ["injected"];
        };
      };
    })
  ]);
}
