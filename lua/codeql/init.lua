local util = require "codeql.util"
local queryserver = require "codeql.queryserver"
local config = require "codeql.config"
local Path = require "plenary.path"
local ts_utils_installed, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
local ts_parsers_installed, ts_parsers = pcall(require, "nvim-treesitter.parsers")
local vim = vim
local range_ns = vim.api.nvim_create_namespace "codeql"

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
  local conf = config.config
  conf.ram_opts = util.resolve_ram()
  dbpath = vim.fn.fnamemodify(vim.trim(dbpath), ":p")
  local database
  if not dbpath then
    util.err_message("Incorrect database: " .. dbpath)
  elseif Path:new(dbpath):is_file() and vim.endswith(dbpath, ".zip") then
    -- extract the zip file
    local db_dir = string.format("%s/codeql_dbs/%s", vim.fn.stdpath "data", vim.fn.fnamemodify(dbpath, ":t:r"))
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
    util.message("Database set to " .. database)
    local metadata = util.database_info(database)
    if not metadata then
      util.err_message("Could not load the database " .. vim.inspect(database))
      return
    end
    metadata.path = database

    if not util.is_blank(config.database) then
      queryserver.unregister_database(function()
        queryserver.register_database(metadata)
      end)
    else
      queryserver.register_database(metadata)
    end
  end
end

local function is_predicate_node(node)
  return node:type() == "charpred" or node:type() == "memberPredicate" or node:type() == "classlessPredicate"
end

local function is_predicate_identifier_node(parent, node)
  if parent then
    return (parent:type() == "charpred" and node:type() == "className")
        or (parent:type() == "classlessPredicate" and node:type() == "predicateName")
        or (parent:type() == "memberPredicate" and node:type() == "predicateName")
  end
end

function M.get_node_at_cursor()
  if not ts_parsers_installed then
    return
  end
  local winnr = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(winnr)
  local cursor_range = { cursor[1] - 1, cursor[2] }
  local root_lang_tree = ts_parsers.get_parser(bufnr)
  if not root_lang_tree then
    return
  end
  local root = root_lang_tree:trees()[1]:root()
  return root:named_descendant_for_range(cursor_range[1], cursor_range[2], cursor_range[1], cursor_range[2]), root
end

function M.get_eval_position()
  local bufnr = vim.api.nvim_get_current_buf()
  if not ts_utils_installed then
    return
  end
  local node, root = M.get_node_at_cursor()
  local orig_node = node
  if not node then
    util.err_message "Error getting node at cursor. Make sure treesitter CodeQL parser is installed"
    return
  end
  local parent = node:parent()
  -- ascend the AST until we get to a predicate node
  while parent and parent ~= root and not is_predicate_node(node) and not is_predicate_identifier_node(parent, node) do
    node = parent
    parent = node:parent()
  end
  if parent == root then
    -- We got to the root node, evaluate the whole query
    return
  elseif is_predicate_identifier_node(parent, node) then
    local srow, scol, erow, ecol = node:range()
    local midname = math.floor((scol + ecol) / 2)
    return { srow + 1, midname, erow + 1, midname }
  elseif is_predicate_node(node) then
    -- descend the predicate node till we find the name node
    for child in node:iter_children() do
      if is_predicate_identifier_node(node, child) then
        util.message(string.format("Evaluating '%s' predicate", ts_utils.get_node_text(child, bufnr)[1]))
        local srow, scol, erow, ecol = child:range()
        local midname = math.floor((scol + ecol) / 2)
        return { srow + 1, midname, erow + 1, midname }
      end
    end
    vim.notify("No predicate identifier node found", 2)
    return
  else
    vim.notify("No predicate node found " .. vim.inspect(orig_node:type()), 2)
  end
end

function M.smart_quick_evaluate()
  local position = M.get_eval_position()
  if position then
    M.query(true, position)
  else
    M.query(false, util.get_current_position())
  end
end

function M.quick_evaluate()
  M.query(true, util.get_current_position())
end

function M.run_query()
  M.query(false, util.get_current_position())
end

function M.query(quick_eval, position)
  local db = config.database
  if not db or not db.path then
    util.err_message "Missing database. Use :SetDatabase command"
    return
  end

  local dbPath = db.path
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
  c = { qlpack = "codeql/cpp-all" },
  cpp = { qlpack = "codeql/cpp-all" },
  java = { qlpack = "codeql/java-all" },
  cs = { qlpack = "codeql/csharp-all" },
  javascript = { qlpack = "codeql/javascript-all" },
  python = { qlpack = "codeql/python-all" },
  ql = { qlpack = "codeql/ql", path = "ide-contextual-queries/" },
  ruby = { qlpack = "codeql/ruby-all", path = "ide-contextual-queries/" },
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
        selectedSourceFile = "/" .. param,
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

function M.load_vcs_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local uri = string.match(bufname, "versionControlProvenance://(.*)")
  local paramlessUri = vim.split(uri, "?")[1]
  local parts={}
  for part in string.gmatch(paramlessUri, "[^%.]+") do
    table.insert(parts, part)
  end
  local extension = parts[#parts]
  local chunks = vim.split(paramlessUri, "/")
  local params = vim.split(uri, "?")[2]
  local node = {}
  if params then
    local pairs = vim.split(params, "&")
    for _,pair in ipairs(pairs) do
      local kv = vim.split(pair, "=")
      node[kv[1]] = kv[2]
    end
  end
  local owner = chunks[1]
  local name = chunks[2]
  local revisionId = chunks[3]
  local path = table.concat(chunks, "/", 4, #chunks)
  util.get_file_contents(owner, name, revisionId, path, function(lines)
    vim.api.nvim_buf_set_lines(bufnr, 1, 1, true, lines)
    print(extension)
    vim.api.nvim_buf_set_option(bufnr, "filetype", extension)
    set_source_buffer_options(bufnr)
    -- move cursor to the node's line
    pcall(vim.api.nvim_win_set_cursor, 0, { tonumber(node.line), 0 })
    vim.cmd "norm! zz"

    -- highlight node
    util.highlight_range(range_ns, tonumber(node.startLine), tonumber(node.endLine), tonumber(node.startColumn), tonumber(node.endColumn))

    -- jump to main window if requested
    if node.stay == "true" then
      vim.fn.win_gotoid(node.panelId)
    end
  end)

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
    vim.cmd [[command! QuickEvalPredicate lua require'codeql'.smart_quick_evaluate()]]
    vim.cmd [[command! -range QuickEval lua require'codeql'.quick_evaluate()]]
    vim.cmd [[command! StopServer lua require'codeql.queryserver'.stop_server()]]
    vim.cmd [[command! History lua require'codeql.history'.menu()]]
    vim.cmd [[command! PrintAST lua require'codeql'.run_print_ast()]]
    vim.cmd [[command! -nargs=1 -complete=file LoadSarif lua require'codeql.loader'.load_sarif_results(<f-args>)]]
    vim.cmd [[command! ArchiveTree lua require'codeql.explorer'.draw()]]
    vim.cmd [[command! -nargs=1 LoadMRVAScan lua require'codeql.mrva.panel'.draw(<f-args>)]]

    -- autocommands
    vim.cmd [[augroup codeql]]
    vim.cmd [[au!]]
    vim.cmd [[au BufEnter * if &ft ==# 'codeql_panel' | execute("lua require'codeql.panel'.apply_mappings()") | endif]]
    vim.cmd [[au BufEnter codeql://* lua require'codeql'.setup_archive_buffer()]]
    vim.cmd [[au BufReadCmd codeql://* lua require'codeql'.load_source_buffer()]]
    vim.cmd [[au BufReadCmd versionControlProvenance://* lua require'codeql'.load_vcs_buffer()]]
    vim.cmd [[autocmd FileType ql lua require'codeql.util'.apply_mappings()]]

    if require("codeql.config").config.format_on_save then
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
