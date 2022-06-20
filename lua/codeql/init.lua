local util = require "codeql.util"
local queryserver = require "codeql.queryserver"
local config = require "codeql.config"
local Path = require "plenary.path"

local M = {}

function M.setup_archive_buffer()
  local bufnr = vim.api.nvim_get_current_buf()

  -- set codeql buffers as scratch buffers
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(bufnr, "swapfile", false)

  -- set mappings
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd [[nmap <buffer>gd <Plug>(CodeQLGoToDefinition)]]
    vim.cmd [[nmap <buffer>gr <Plug>(CodeQLFindReferences)]]
  end)

  -- load definitions and references
  M.load_definitions(bufnr)
end

function M.load_definitions(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)

  -- check if file has already been processed
  local defs = require "codeql.defs"
  local fname = vim.split(bufname, "://")[2]
  if defs.processedFiles[fname] then
    return
  end

  -- query the buffer for defs and refs
  M.run_templated_query("localDefinitions", fname)
  M.run_templated_query("localReferences", fname)

  -- prevent further definition queries from being run on the same buffer
  defs.processedFiles[fname] = true
end

function M.set_database(dbpath)
  local conf = config.get_config()
  conf.ram_opts = util.resolve_ram()
  dbpath = vim.fn.fnamemodify(vim.trim(dbpath), ":p")
  local database
  if not dbpath then
    util.err_message("Incorrect database: " .. dbpath)
  elseif Path:new(dbpath):is_file() and vim.endswith(dbpath, ".zip") then
    -- extract the zip file
    local db_dir = string.format("%s/codeql_dbs", vim.fn.stdpath "data")
    -- make sure db_dir exists
    vim.fn.mkdir(vim.fn.fnamemodify(db_dir, ":h"), "p", 0777)
    -- extract the zip file
    vim.fn.system(string.format("unzip -q %s -d %s", dbpath, db_dir))
    local db_name = vim.trim(vim.fn.system(string.format('unzip -Z1 %s | head -n 1 | cut -d "/" -f 1', dbpath)))
    database = string.format("%s/%s/", db_dir, db_name)
  elseif util.is_dir(dbpath) then
    database = dbpath
    if not vim.endswith(database, "/") then
      database = database .. "/"
    end
  else
    util.err_message("Incorrect database: " .. dbpath)
  end
  if database then
    print("Database set to " .. database)
    local metadata = util.database_info(database)
    metadata.path = database
    queryserver.register_database(metadata)
    -- show the side tree
    vim.cmd [[ArchiveTree]]
  end
end

local function is_predicate_node(node)
  return node:type() == "charpred" or node:type() == "memberPredicate" or node:type() == "classlessPredicate"
end

local function is_predicate_identifier_node(predicate_node, node)
  return (predicate_node:type() == "charpred" and node:type() == "className")
      or (predicate_node:type() == "classlessPredicate" and node:type() == "predicateName")
      or (predicate_node:type() == "memberPredicate" and node:type() == "predicateName")
end

function M.get_enclosing_predicate_position()
  local ok, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
  if not ok then
    return nil
  end
  local winnr = vim.api.nvim_get_current_win()
  local ok, node = pcall(ts_utils.get_node_at_cursor, winnr)
  if not ok or not node then
    util.err_message "Error getting node at cursor. Make sure treesitter CodeQL parser is installed"
    return
  end
  local parent = node:parent()
  local root = ts_utils.get_root_for_node(node)
  while parent and parent ~= root and not is_predicate_node(node) do
    node = parent
    parent = node:parent()
  end
  if is_predicate_node(node) then
    for child in node:iter_children() do
      if is_predicate_identifier_node(node, child) then
        print(string.format("Evaluating '%s' predicate", child))
        local srow, scol, erow, ecol = child:range()
        local midname = math.floor((scol + ecol) / 2)
        return { srow + 1, midname, erow + 1, midname }
      end
    end
    vim.notify("No predicate identifier node found", 2)
    return
  else
    vim.notify("No predicate node found", 2)
  end
end

function M.get_current_position()
  local srow, scol, erow, ecol

  if vim.fn.getpos("'<")[2] == vim.fn.getcurpos()[2] and vim.fn.getpos("'<")[3] == vim.fn.getcurpos()[3] then
    srow = vim.fn.getpos("'<")[2]
    scol = vim.fn.getpos("'<")[3]
    erow = vim.fn.getpos("'>")[2]
    ecol = vim.fn.getpos("'>")[3]

    ecol = ecol == 2147483647 and 1 + vim.fn.len(vim.fn.getline(erow)) or 1 + ecol
  else
    srow = vim.fn.getcurpos()[2]
    scol = vim.fn.getcurpos()[3]
    erow = vim.fn.getcurpos()[2]
    ecol = vim.fn.getcurpos()[3]
  end

  return { srow, scol, erow, ecol }
end

function M.quick_evaluate_enclosing_predicate()
  local position = M.get_enclosing_predicate_position()
  if position then
    M.query(true, position)
  end
end

function M.quick_evaluate()
  M.query(true, M.get_current_position())
end

function M.run_query()
  M.query(false, M.get_current_position())
end

function M.query(quick_eval, position)
  local db = config.database
  if not db then
    util.err_message "Missing database. Use :SetDatabase command"
    return
  end

  local dbPath = config.database.path
  local queryPath = vim.fn.expand "%:p"

  local libPaths = util.resolve_library_path(queryPath)
  if not libPaths then
    vim.notify(string.format("Cannot resolve QL library paths for %s", queryPath), 2)
    return
  end

  local opts = {
    quick_eval = quick_eval,
    bufnr = vim.api.nvim_get_current_buf(),
    query = queryPath,
    dbPath = dbPath,
    startLine = position[1],
    startColumn = position[2],
    endLine = position[3],
    endColumn = position[4],
    metadata = util.query_info(queryPath),
    libraryPath = libPaths.libraryPath,
    dbschemePath = libPaths.dbscheme,
  }

  queryserver.run_query(opts)
end

local templated_queries = {
  c = { qlpack = "codeql/cpp-queries" },
  cpp = { qlpack = "codeql/cpp-queries" },
  java = { qlpack = "codeql/java-queries" },
  cs = { qlpack = "codeql/csharp-queries" },
  javascript = { qlpack = "codeql/javascript-queries" },
  python = { qlpack = "codeql/python-queries" },
  ql = { qlpack = "codeql/ql", path = "ide-contextual/" },
  ruby = { qlpack = "codeql/ruby-queries", path = "ide-contextual/" },
  go = { qlpack = "codeql/go-all" },
}

function M.run_print_ast()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.fn.bufname(bufnr)

  -- not a codeql:/ buffer
  if not vim.startswith(bufname, "codeql:/") then
    return
  end

  local fname = vim.split(bufname, "://")[2]
  M.run_templated_query("printAst", fname)
end

function M.run_templated_query(query_name, param)
  local bufnr = vim.api.nvim_get_current_buf()
  local dbPath = config.database.path
  local ft = vim.bo[bufnr]["ft"]
  if not templated_queries[ft] then
    --util.err_message(format('%s does not support %s file type', query_name, ft))
    return
  end
  local qlpack = templated_queries[ft].qlpack
  local path_modifier = templated_queries[ft].path or ""
  local qlpacks = util.resolve_qlpacks()
  if qlpacks[qlpack] then
    local path = qlpacks[qlpack][1]
    local queryPath = string.format("%s/%s%s.ql", path, path_modifier, query_name)
    if util.is_file(queryPath) then
      local templateValues = {
        selectedSourceFile = {
          values = {
            tuples = { { { stringValue = "/" .. param } } },
          },
        },
      }
      local libPaths = util.resolve_library_path(queryPath)
      if not libPaths then
        vim.notify("Cannot resolve QL library paths for: " .. query_name, 2)
        return
      end
      local opts = {
        quick_eval = false,
        bufnr = bufnr,
        query = queryPath,
        dbPath = dbPath,
        metadata = util.query_info(queryPath),
        libraryPath = libPaths.libraryPath,
        dbschemePath = libPaths.dbscheme,
        templateValues = templateValues,
      }
      require("codeql.queryserver").run_query(opts)
    else
      vim.notify("Cannot find a valid query: " .. queryPath, 2)
    end
  end

end

local function set_source_buffer_options(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd "normal! ggdd"
    pcall(vim.cmd, "filetype detect")
    vim.api.nvim_buf_set_option(bufnr, "modified", false)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    vim.cmd "doau BufEnter"
  end)
end

local function open_from_archive(bufnr, path)
  local zipfile = config.database.sourceArchiveZip
  local content = vim.fn.systemlist(string.format("unzip -p -- %s %s", zipfile, path))
  vim.api.nvim_buf_set_lines(bufnr, 1, 1, true, content)
end

local function open_from_sarif(bufnr, path)
  local sarif = util.read_json_file(config.sarif.path)
  if config.sarif.hasArtifacts then
    local artifacts = sarif.runs[1].artifacts
    for _, artifact in ipairs(artifacts) do
      local uri = artifact.location.uri
      if uri == path then
        local content = vim.split(artifact.contents.text, "\n")
        vim.api.nvim_buf_set_lines(bufnr, 1, 1, true, content)
        break
      end
    end
  end
end

function M.load_source_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local path = string.match(bufname, "codeql://(.*)")
  if config.sarif.path and config.sarif.hasArtifacts then
    open_from_sarif(bufnr, path)
    -- for snippets, do nothing since the buffer will be written from the `panel.jump_to_code`
  elseif config.database.sourceArchiveZip then
    open_from_archive(bufnr, path)
  else
    vim.notify "Cannot find source file"
  end
  set_source_buffer_options(bufnr)
end

function M.setup(opts)
  if vim.fn.executable "codeql" then
    config.setup(opts or {})

    -- highlight groups
    vim.cmd [[highlight default link CodeqlAstFocus CursorLine]]
    vim.cmd [[highlight default link CodeqlRange Error]]

    -- commands
    vim.cmd [[command! -nargs=1 -complete=file SetDatabase lua require'codeql'.set_database(<f-args>)]]
    vim.cmd [[command! UnsetDatabase lua require'codeql.queryserver'.unregister_database()]]
    vim.cmd [[command! CancelQuery lua require'codeql.queryserver'.cancel_query()]]
    vim.cmd [[command! RunQuery lua require'codeql'.run_query()]]
    vim.cmd [[command! QuickEvalPredicate lua require'codeql'.quick_evaluate_enclosing_predicate()]]
    vim.cmd [[command! -range QuickEval lua require'codeql'.quick_evaluate()]]
    vim.cmd [[command! StopServer lua require'codeql.queryserver'.stop_server()]]
    vim.cmd [[command! History lua require'codeql.history'.menu()]]
    vim.cmd [[command! PrintAST lua require'codeql'.run_print_ast()]]
    vim.cmd [[command! -nargs=1 -complete=file LoadSarif lua require'codeql.loader'.load_sarif_results(<f-args>)]]
    vim.cmd [[command! ArchiveTree lua require'codeql.explorer'.draw()]]
    vim.cmd [[command! -nargs=1 LoadMVRAScan lua require'codeql.mvra'.load_scan(<f-args>)]]

    -- autocommands
    vim.cmd [[augroup codeql]]
    vim.cmd [[au!]]
    vim.cmd [[au BufEnter * if &ft ==# 'codeql_panel' | execute("lua require'codeql.panel'.apply_mappings()") | endif]]
    vim.cmd [[au BufEnter codeql://* lua require'codeql'.setup_archive_buffer()]]
    vim.cmd [[au BufReadCmd codeql://* lua require'codeql'.load_source_buffer()]]
    if require("codeql.config").get_config().format_on_save then
      vim.cmd [[autocmd FileType ql autocmd BufWrite <buffer> lua vim.lsp.buf.formatting()]]
    end
    vim.cmd [[augroup END]]

    -- mappings
    vim.cmd [[nnoremap <Plug>(CodeQLGoToDefinition) <cmd>lua require'codeql.defs'.find_at_cursor('definitions')<CR>]]
    vim.cmd [[nnoremap <Plug>(CodeQLFindReferences) <cmd>lua require'codeql.defs'.find_at_cursor('references')<CR>]]
    vim.cmd [[nnoremap <Plug>(CodeQLGrepSource) <cmd>lua require'codeql.grepper'.grep_source()<CR>]]
  end
end

return M
