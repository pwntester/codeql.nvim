# CodeQL.nvim

Neovim plugin to help writing and testing CodeQL queries.

[![asciicast](https://asciinema.org/a/318276.svg)](https://asciinema.org/a/318276)

## Features 

- Syntax highlighting for CodeQL query language
- Query execution
- Quick query evaluation
- Result browser

## Requirements

- Neovim 0.5+

## Usage

### Query pack 

Create `qlpack.yaml` (see [QL packs](https://help.semmle.com/codeql/codeql-cli/reference/qlpack-overview.html)). E.g:

```
name: test 
version: 0.0.1
libraryPathDependencies: [codeql-java]
```

### Query

Create `.ql` file with query 

### Set Database

Use `SetDatabase <path to db>` to let the plugin know what DB to work with

### Run query or eval predicates

Use `RunQuery` or `QuickEval` commands or `qr`, `qe` shortcuts respectively to run the query or evaluate the predicate under the cursor.

## Commands
- `SetDatabase <path to db>`: Required before running any query.
- `RunQuery`: Runs the query on the current buffer. Requires a DB to be set first.
- `QuickEval`: Quick evals the predicate or selection under cursor. Requires a DB to be set first.

## Result Browser
After running a query or quick evaluating a predicate, results will be rendered in a special panel.

- `o`: Collapses/Expands result
- `Enter` (on a visitable result node): Opens node file in vim and moves cursor to window with source code file 
- `p`: Similar to `Enter` but does not keep cursor on the results panel
- `N` (on a Paths node): Change to next path
- `P` (on a Paths node): Change to previous path
 
## Language Server Protocol
This plugin does not provide any support for the Language Server Protocol (LSP). But in order to have the best CodeQL writing experience it is recommended to configure a LSP client to connect to the CodeQL Language Server.

There are many LSP clients in the NeoVim ecosystem. The following clients have been tested with CodeQL Language Server:

### Neovim Built-In LSP

It is possible to configure the built-in LSP client without any additional plugins, but a default configuration for the CodeQL Language Server has been added to [Nvim-LSP](https://github.com/neovim/nvim-lsp). If you are using `vim-plug`, it is a matter
of adding following line to you vim config:

```
Plug 'neovim/nvim-lsp'
```

Using this client, it is only required to configure the client with:

``` lua
local nvim_lsp = require 'nvim_lsp'

nvim_lsp.codeqlls.setup{
    on_attach = on_attach_callback;
    settings = {
        search_path = {'~/codeql-home/codeql-repo'};
    };
}
```
NOTE: change `search_path` to the path where the [QL](https://github.com/Semmle/ql) repo has been installed to.

It is also recommended to add an `on_attach` callback to define LSP mappings. E.g:

``` lua
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
        search_path = {'~/codeql-home/codeql-repo'};
    };
}
```

Check my [dotfiles](https://github.com/pwntester/dotfiles/blob/master/config/nvim/lua/lsp-config.lua) for examples on how to configure the NVIM LSP client.
