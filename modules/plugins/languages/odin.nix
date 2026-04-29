{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (builtins) attrNames;
  inherit (lib.options) mkEnableOption mkOption literalExpression;
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.types) enum package listOf;
  inherit (lib.nvim.dag) entryAfter;
  inherit (lib) genAttrs;
  inherit (lib.nvim.types) mkGrammarOption;

  cfg = config.vim.languages.odin;

  defaultServers = ["ols"];
  servers = ["ols"];
  defaultDebugger = "codelldb";
  debuggers = {
    codelldb = {
      package = pkgs.lldb;
      dapConfig = ''
        dap.adapters.codelldb = {
          type = 'executable',
          command = '${cfg.dap.package}/bin/lldb-dap',
          name = 'codelldb'
        }
      '';
    };
  };
in {
  options.vim.languages.odin = {
    enable = mkEnableOption "Odin language support";

    treesitter = {
      enable =
        mkEnableOption "Odin treesitter"
        // {
          default = config.vim.languages.enableTreesitter;
          defaultText = literalExpression "config.vim.languages.enableTreesitter";
        };
      package = mkGrammarOption pkgs "odin";
    };

    lsp = {
      enable =
        mkEnableOption "Odin LSP support"
        // {
          default = config.vim.lsp.enable;
          defaultText = literalExpression "config.vim.lsp.enable";
        };

      servers = mkOption {
        type = listOf (enum servers);
        default = defaultServers;
        description = "Odin LSP server to use";
      };
    };

    dap = {
      enable =
        mkEnableOption "Enable Odin Debug Adapter"
        // {
          default = config.vim.languages.enableDAP;
          defaultText = literalExpression "config.vim.languages.enableDAP";
        };

      debugger = mkOption {
        description = "Odin debugger to use";
        type = enum (attrNames debuggers);
        default = defaultDebugger;
      };

      package = mkOption {
        description = "Odin debugger package.";
        type = package;
        default = debuggers.${cfg.dap.debugger}.package;
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.treesitter.enable {
      vim.treesitter.enable = true;
      vim.treesitter.grammars = [cfg.treesitter.package];
    })

    (mkIf cfg.lsp.enable {
      vim.lsp = {
        presets = genAttrs cfg.lsp.servers (_: {enable = true;});
        servers = genAttrs cfg.lsp.servers (_: {
          filetypes = ["odin"];
        });
      };
    })

    (mkIf cfg.dap.enable {
      vim = {
        startPlugins = ["nvim-dap-odin"];
        debugger.nvim-dap.sources.odin-debugger = debuggers.${cfg.dap.debugger}.dapConfig;
        pluginRC.nvim-dap-odin = entryAfter ["nvim-dap"] ''
          require('nvim-dap-odin').setup({
            notifications = false -- contains no useful information
          })
        '';
        debugger.nvim-dap.enable = true;
      };
    })
  ]);
}
