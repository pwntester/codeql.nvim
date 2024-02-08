# CodeQL.nvim

Neovim plugin to help writing and testing CodeQL queries.

## Features

- Syntax highlighting for CodeQL query language
- Query execution
- Quick query evaluation
- Query history
- Result browser
- Source archive grepper
- Source archive explorer
- SARIF viewer
- MRVA results browser (requires [`gh-mrva`](https://github.com/GitHubSecurityLab/gh-mrva))

## Requirements

- [neovim](https://github.com/neovim/neovim)
- [ugrep](https://github.com/Genivia/ugrep)

## Install

```lua
use {
  "pwntester/codeql.nvim",
  requires = {
    "MunifTanjim/nui.nvim",
    "nvim-lua/telescope.nvim",
    "kyazdani42/nvim-web-devicons",
    {
      's1n7ax/nvim-window-picker',
      tag = 'v1.*',
      config = function()
        require'window-picker'.setup({
          autoselect_one = true,
          include_current = false,
          filter_rules = {
            bo = {
              filetype = {
                "codeql_panel",
                "codeql_explorer",
                "qf",
                "TelescopePrompt",
                "TelescopeResults",
                "notify",
                "noice",
                "NvimTree",
                "neo-tree",
              },
              buftype = { 'terminal' },
            },
          },
          current_win_hl_color = '#e35e4f',
          other_win_hl_color = '#44cc41',
        })
      end,
    }
  },
  config = function()
    require("codeql").setup {}
  end
}
```

## Usage

### Query

### Database

Use `QL database set <path to db>` to let the plugin know what DB to work with.
Use `QL database unset` to unregister the current registered database.

### Run query or eval predicates

Use `QL query run` or `QL query quick-eval` commands or `qr`, `qp` shortcuts respectively to run the query or evaluate the predicate under the cursor.

## Configuration options

- additional_packs: List of codeql qlpacks to use
- max_ram: Max RAM memory to be used by CodeQL
- job_timeout: Timeout for running sync jobs (default: 15000)

eg:

```lua
require("codeql").setup {
  results = {
    max_paths = 10,
    max_path_depth = nil,
  },
  panel = {
    width = 50,
    pos = "botright",
    group_by = "sink", -- "source"
    show_filename = true,
    long_filename = false,
    context_lines = 3,
  },
  max_ram = 32000,
  job_timeout = 15000,
  format_on_save = true,
  additional_packs = {
    "/Users/pwntester/codeql-home/codeql",
    "/Users/pwntester/codeql-home/codeql-go",
    "/Users/pwntester/codeql-home/codeql-ruby",
    "./codeql",
  },
  mappings = {
    run_query = { modes = { "n" }, lhs = "<space>qr", desc = "run query" },
    quick_eval = { modes = { "x", "n" }, lhs = "<space>qe", desc = "quick evaluate" },
    quick_eval_predicate = { modes = { "n" }, lhs = "<space>qp", desc = "quick evaluate enclosing predicate" },
  },
}
```

## Commands

- `QL database set <path to db>`: Required before running any query.
- `QL database unset`: Unregister current database.
- `QL database browse`: Shows source archive tree explorer
- `QL query run`: Runs the query on the current buffer. Requires a DB to be set first.
- `QL query eval`: Quick evals the predicate or selection under cursor. Requires a DB to be set first.
- `QL query cancel`: Cancels current query.
- `QL history list`: Shows a menu to render results of previous queries (on the same nvim session).
- `QL server stop`: Stops the query server associated with the query buffer. A new one will be started upon query evaluation.
- `QL ast print`: On a `ql:/` buffer, prints the AST of the current file.
- `QL sarif load <path to SARIF file>`: Loads the issues of a SARIF file. To browse the results, use `QL db set` before.
- `QL sarif permalink`: Copies a permalink to the current line of a SARIF file.
- `QL sarif browse`: Open the file in GitHub.
- `QL mrva load <name of MRVA session>`: Loads results of MRVA scan.

## Mappings

- `gd`: On a `ql:/` file, jumps to the symbol definition.
- `gr`: On a `ql:/` file, show symbol references in the QuickFix window.
- `<leader>qr`: Runs the current query.
- `<leader>qe`: Quick evaluate the selected predicate.
- `<leader>qp`: Quick evaluate the enclosing predicate.
- `<Plug>(CodeQLGrepSource)`: shows a telescope menu to grep the source archive

## Result Browser

After running a query or quick evaluating a predicate, results will be rendered in a special panel.

- `o`: collapses/Expands result
- `Enter` (on a visitable result node): opens node file in nvim and moves cursor to window with source code file
- `p`: similar to `Enter` but keeps cursor on the results panel
- `N`: change to next path
- `P`: change to previous path
- `f`: filter issues by issue label
- `F`: filter issues
- `c`: clear filter
- `t`: open all folds
- `T`: closes all folds
- `q`: closes result panel
- `s`: show context snippet

## Language Server Protocol

This plugin does not provide any support for the Language Server Protocol (LSP). But in order to have the best CodeQL writing experience it is recommended to configure a LSP client to connect to the CodeQL Language Server.

There are many LSP clients in the NeoVim ecosystem. The following clients have been tested with CodeQL Language Server:

### Neovim Built-In LSP

It is possible to configure the built-in LSP client without any additional plugins, but a default configuration for the CodeQL Language Server has been added to [Nvim-LSP](https://github.com/neovim/nvim-lsp). If you are using `packer`, it is a matter of adding following line to you vim config:

```lua
use 'neovim/nvim-lsp'
```

Using this client, it is only required to configure the client with:

```lua
local nvim_lsp = require 'nvim_lsp'

nvim_lsp.codeqlls.setup{
    on_attach = on_attach_callback;
    settings = {
        additional_packs = {'~/codeql-home/codeql-repo'};
    };
}
```

NOTE: change `additional_packs` to the path where the [CodeQL](https://github.com/github/codeql) repo has been installed to.

It is also recommended to add an `on_attach` callback to define LSP mappings. E.g:

```lua
local function on_attach_callback(client, bufnr)
    api.nvim_buf_set_keymap(bufnr, "n", "gD", "<Cmd>lua show_diagnostics_details()<CR>", { silent = true; })
    api.nvim_buf_set_keymap(bufnr, "n", "gd", "<Cmd>lua vim.lsp.buf.definition()<CR>", { silent = true; })
    api.nvim_buf_set_keymap(bufnr, "n", "gi", "<Cmd>lua vim.lsp.buf.implementation()<CR>", { silent = true; })
    api.nvim_buf_set_keymap(bufnr, "n", "gK", "<Cmd>lua vim.lsp.buf.hover()<CR>", { silent = true; })
    api.nvim_buf_set_keymap(bufnr, "n", "gh", "<Cmd>lua vim.lsp.buf.signature_help()<CR>", { silent = true; })
    api.nvim_buf_set_keymap(bufnr, "n", "gr", "<Cmd>lua vim.lsp.buf.references()<CR>", { silent = true; })
    api.nvim_buf_set_keymap(bufnr, "n", "gF", "<Cmd>lua vim.lsp.buf.formatting()<CR>", { silent = true; })
    api.nvim_command [[autocmd CursorHold  <buffer> lua vim.lsp.buf.document_highlight()]]
    api.nvim_command [[autocmd CursorHoldI <buffer> lua vim.lsp.buf.document_highlight()]]
    api.nvim_command [[autocmd CursorMoved <buffer> lua vim.lsp.util.buf_clear_references()]]
end

local nvim_lsp = require 'nvim_lsp'

nvim_lsp.codeqlls.setup{
    on_attach = on_attach_callback;
    settings = {
        additional_packs = {'~/codeql-home/codeql-repo'};
    };
}
```

Check my [dotfiles](https://github.com/pwntester/dotfiles/blob/master/config/nvim/lua/lsp_config.lua) for examples on how to configure the NVIM LSP client.

### Coc.nvim

It is possible to add codeql language server to `coc.nvim` using `coc-settings.json` as an
[executable language server](https://github.com/neoclide/coc.nvim/wiki/Language-servers)

```json
{
  "languageserver": {
    "codeql": {
      "command": "<path to codeql binary>",
      "args": [
        "execute",
        "language-server",
        "--check-errors=ON_CHANGE",
        "--search-path=./:<path to semmle/ql repo maybe>:<any more paths>",
        "-q"
      ],
      "filetypes": ["ql"],
      "rootPatterns": ["qlpack.yml"],
      "requireRootPattern": true
    }
  }
}
```

## 🙏 Say Thanks

If you like this plugin and would like to buy me a coffee, you can!

[<img src="https://cdn.buymeacoffee.com/buttons/v2/default-violet.png" alt="BuyMeACoffee" width="140">](https://www.buymeacoffee.com/pwntester)

[![GitHub Sponsors](https://img.shields.io/github/sponsors/pwntester?style=social)](https://github.com/sponsors/pwntester)
