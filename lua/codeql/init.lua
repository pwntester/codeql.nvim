local util = require "codeql.util"
local queryserver = require "codeql.queryserver"
local config = require "codeql.config"
local Path = require "plenary.path"
local vim = vim

local M = {}

function M.list_databases()
  local pok, pickers = pcall(require, "telescope.pickers")
  local fok, finders = pcall(require, "telescope.finders")
  local cok, conf = pcall(require, "telescope.config")
  local aok, actions = pcall(require, "telescope.actions")
  local sok, action_state = pcall(require, "telescope.actions.state")
  local uok, utils = pcall(require, "telescope.utils")
  if not (pok and fok and cok and aok and sok) then
    util.err_message "Telescope is not installed"
    return
  end
  local cmd = config.values.find_databases_cmd
  if not cmd then
    util.err_message "No find_databases_cmd set in config"
    return
  end
  if not type(cmd) == "table" then
    util.err_message "find_databases_cmd should be a list of strings"
    return
  end
  local opts = config.values.telescope_opts
  local entry_maker = config.values.database_list_entry_maker
  local previewer = config.values.database_list_previewer

  local results = utils.get_os_command_output(cmd)
  pickers
    .new(opts, {
      prompt_title = "CodeQL Databases",
      finder = finders.new_table {
        results = results,
        entry_maker = entry_maker,
      },
      previewer = previewer(opts),
      sorter = conf.values.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          M.set_database(selection.value)
        end)
        return true
      end,
    })
    :find()
end

function M.set_database(dbpath)
  local conf = config.values
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

function M.unset_database(dbpath)
  if not util.is_blank(config.database) then
    queryserver.unregister_database(function() end)
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

---@return TSNode?, TSNode?
function M.get_node_at_cursor()
  local winnr = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(winnr)
  local cursor_range = { cursor[1] - 1, cursor[2] }
  local ok, root_lang_tree = pcall(vim.treesitter.get_parser, bufnr, vim.treesitter.language.get_lang(vim.bo.filetype))
  if not ok then
    return
  end
  local root = root_lang_tree:trees()[1]:root()
  return root:named_descendant_for_range(cursor_range[1], cursor_range[2], cursor_range[1], cursor_range[2]), root
end

function M.get_eval_position()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.treesitter.highlighter.active[bufnr] == nil then
    util.err_message "No treesitter parser"
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
        util.message(string.format("Evaluating '%s' predicate", vim.treesitter.get_node_text(child, bufnr)[1]))
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
    util.err_message "Missing database. Use `:QL db set` command"
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
  yaml = { qlpack = "codeql/actions-all", path = "ql/lib/ide-contextual-queries/" },
  yml = { qlpack = "codeql/actions-all", path = "ql/lib/ide-contextual-queries/" },
  swift = { qlpack = "codeql/swift-all", path = "ide-contextual-queries/" },
}

function M.run_print_cfg()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.fn.bufname(bufnr)

  -- not a ql:/ buffer
  if not vim.startswith(bufname, "ql:/") then
    util.err_message "Not a ql:/ buffer"
    return
  end

  local fname = vim.split(bufname, "://")[2]
  M.run_templated_query("printCfg", fname)
end

function M.run_print_ast()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.fn.bufname(bufnr)

  -- not a ql:/ buffer
  if not vim.startswith(bufname, "ql:/") then
    util.err_message "Not a ql:/ buffer"
    return
  end

  local fname = vim.split(bufname, "://")[2]
  M.run_templated_query("printAst", fname)
end

function M.run_templated_query(query_name, fname)
  local bufnr = vim.api.nvim_get_current_buf()
  local dbPath = config.database.path
  local ft = vim.fn.fnamemodify(fname, ":e")
  if not templated_queries[ft] then
    util.err_message(string.format("%s does not support %s file type", query_name, ft))
    return
  end
  local qlpack = templated_queries[ft].qlpack
  local path_modifier = templated_queries[ft].path or ""
  local qlpacks = util.resolve_qlpacks()
  local path
  if qlpacks and qlpacks[qlpack] then
    path = qlpacks[qlpack][1]
  else
    path = vim.fn.getcwd()
  end
  local position = vim.api.nvim_win_get_cursor(0)
  local queryPath = string.format("%s/%s%s.ql", path, path_modifier, query_name)
  if util.is_file(queryPath) then
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
      templateValues = {
        selectedSourceFile = "/" .. fname,
        selectedSourceLine = tostring(position[1]),
        selectedSourceColumn = tostring(position[2] + 1),
      },
    }
    require("codeql.queryserver").run_query(opts)
  end
end

function M.get_permalink()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local uri = string.match(bufname, "ql://(.*)")
  if not uri then
    util.err_message "Cannot copy permalink for this buffer"
    return
  end
  local chunks = vim.split(uri, "/")
  if #chunks < 4 then
    util.err_message "Cannot copy permalink for this buffer"
    return
  end
  local owner = chunks[1]
  local name = chunks[2]
  local revisionId = chunks[3]
  local path = table.concat(chunks, "/", 4, #chunks)
  return string.format("https://github.com/%s/%s/blob/%s/%s#L%d", owner, name, revisionId, path, line)
end

function M.copy_permalink()
  local permalink = M.get_permalink()
  vim.fn.setreg("+", permalink)
end

function M.open_in_browser()
  local permalink = M.get_permalink()
  -- replace github.com with github.dev
  permalink = string.gsub(permalink, "github.com", "github.dev")
  vim.fn.system(string.format("open %s", permalink))
end

function M.deprecated(cmd, replacement)
  if not replacement then
    replacement = ":QL"
  end
  vim.notify("'" .. cmd .. "'command is deprecated. Please use `" .. replacement .. "` instead.")
end

function M.setup(opts)
  if vim.fn.executable "codeql" then
    config.setup(opts or {})

    -- highlight groups
    vim.cmd [[highlight default link CodeqlAstFocus CursorLine]]
    vim.cmd [[highlight default link CodeqlRange Error]]

    -- deprecated commands
    vim.cmd [[command! -nargs=1 -complete=file SetDatabase lua require'codeql'.deprecated("SetDatabase");require'codeql'.set_database(<f-args>)]]
    vim.cmd [[command! UnsetDatabase lua require'codeql'.deprecated("UnsetDatabase");require'codeql.queryserver'.unregister_database()]]
    vim.cmd [[command! CancelQuery lua require'codeql'.deprecated("CancelQuery");require'codeql.queryserver'.cancel_query()]]
    vim.cmd [[command! RunQuery lua require'codeql'.deprecated("RunQuery");require'codeql'.run_query()]]
    vim.cmd [[command! QuickEvalPredicate require'codeql'.deprecated("QuickEvalPredicate");lua require'codeql'.smart_quick_evaluate()]]
    vim.cmd [[command! -range QuickEval lua require'codeql'.deprecated("QuickEval");require'codeql'.quick_evaluate()]]
    vim.cmd [[command! StopServer lua require'codeql'.deprecated("StopServer");require'codeql.queryserver'.stop_server()]]
    vim.cmd [[command! History lua require'codeql'.deprecated("History");require'codeql.history'.menu()]]
    vim.cmd [[command! PrintAST lua require'codeql'.deprecated("PrintAST");require'codeql'.run_print_ast()]]
    vim.cmd [[command! -nargs=1 -complete=file LoadSarif lua require'codeql'.deprecated("LoadSarif");require'codeql.loader'.load_sarif_results(<f-args>)]]
    vim.cmd [[command! ArchiveTree lua require'codeql'.deprecated("ArchiveTree");require'codeql.explorer'.draw()]]
    vim.cmd [[command! -nargs=1 LoadMRVAScan lua require'codeql'.deprecated("LoadMRVAScan");require'codeql.mrva.panel'.load(<f-args>)]]
    vim.cmd [[command! CopyPermalink lua require'codeql'.deprecated("CopyPermalink");require'codeql'.copy_permalink()]]
    -- new QL command
    vim.api.nvim_create_user_command("QL", function(copts)
      require("codeql").command(unpack(copts.fargs))
    end, { complete = require("codeql").command_complete, nargs = "*" })
    -- autocommands
    vim.cmd [[augroup codeql]]
    vim.cmd [[au!]]
    vim.cmd [[au BufEnter * if &ft ==# 'codeql_panel' | execute("lua require'codeql.panel'.apply_mappings()") | endif]]
    vim.cmd [[autocmd FileType ql lua require'codeql.util'.apply_mappings()]]

    if require("codeql.config").values.format_on_save then
      vim.cmd [[autocmd FileType ql autocmd BufWrite <buffer> lua vim.lsp.buf.format()]]
    end
    vim.cmd [[augroup END]]

    -- mappings
    vim.cmd [[nnoremap <Plug>(CodeQLGoToDefinition) <cmd>lua require'codeql.defs'.find_at_cursor('definitions')<CR>]]
    vim.cmd [[nnoremap <Plug>(CodeQLFindReferences) <cmd>lua require'codeql.defs'.find_at_cursor('references')<CR>]]
  end
end

local commands = {
  database = {
    set = {
      description = "Set the database to use for CodeQL queries",
      args = {
        {
          name = "database",
          description = "The path to the database to use",
          type = "string",
        },
      },
      handler = function(args)
        M.set_database(args)
      end,
    },
    unset = {
      description = "Unset the database to use for CodeQL queries",
      handler = function()
        M.unset_database()
      end,
    },
    browse = {
      description = "Browse the CodeQL database",
      handler = function()
        require("codeql.explorer").draw()
      end,
    },
    grep = {
      description = "Grep the CodeQL database",
      handler = function()
        require("codeql.grepper").grep_source()
      end,
    },
    list = {
      description = "List the CodeQL databases known to CodeQL.nvim",
      handler = function()
        M.list_databases()
      end,
    },
  },
  query = {
    run = {
      description = "Run the current query",
      handler = function()
        M.run_query()
      end,
    },
    cancel = {
      description = "Cancel the current query",
      handler = function()
        require("codeql.queryserver").cancel_query()
      end,
    },
    eval = {
      description = "Evaluate the current predicate or statements",
      handler = function()
        M.smart_quick_evaluate()
      end,
    },
  },
  server = {
    stop = {
      description = "Stop the CodeQL query server",
      handler = function()
        require("codeql.queryserver").stop_server()
      end,
    },
  },
  history = {
    list = {
      description = "View the CodeQL query history",
      handler = function()
        require("codeql.history").menu()
      end,
    },
  },
  view = {
    ast = {
      description = "Print the AST for the current query",
      handler = function()
        M.run_print_ast()
      end,
    },
    cfg = {
      description = "Print the CFG for the current scope",
      handler = function()
        M.run_print_cfg()
      end,
    },
  },
  ast = {
    print = {
      description = "Print the AST for the current query",
      handler = function()
        M.deprecated("QL ast print", "QL view ast")
      end,
    },
  },
  sarif = {
    load = {
      description = "Load a SARIF file",
      args = {
        {
          name = "sarif",
          description = "The path to the SARIF file to load",
          type = "string",
        },
      },
      handler = function(args)
        require("codeql.loader").load_sarif_results(args)
      end,
    },
    ["permalink"] = {
      description = "Copy a permalink to the current SARIF result",
      handler = function()
        M.copy_permalink()
      end,
    },
    ["browse"] = {
      description = "Copy a permalink to the current SARIF result",
      handler = function()
        M.open_in_browser()
      end,
    },
  },
  mrva = {
    list = {
      description = "List the MRVA scans",
      handler = function()
        require("codeql.mrva.panel").list_sessions()
      end,
    },
    load = {
      description = "Load an MRVA scan",
      args = {
        {
          name = "scan",
          description = "The path to the MRVA scan to load",
          type = "string",
        },
      },
      handler = function(args)
        require("codeql.mrva.panel").load(args)
      end,
    },
  },
}
-- define an alias for database
commands["db"] = commands["database"]

function M.command_complete(argLead, cmdLine)
  -- ArgLead		the leading portion of the argument currently being completed on
  -- CmdLine		the entire command line
  -- CursorPos	the cursor position in it (byte index)
  local command_keys = vim.tbl_keys(commands)
  local parts = vim.split(vim.trim(cmdLine), " ")

  local get_options = function(options)
    local valid_options = {}
    for _, option in pairs(options) do
      if string.sub(option, 1, #argLead) == argLead then
        table.insert(valid_options, option)
      end
    end
    return valid_options
  end

  if #parts == 1 then
    return command_keys
  elseif #parts == 2 and not vim.tbl_contains(command_keys, parts[2]) then
    return get_options(command_keys)
  elseif #parts == 2 and vim.tbl_contains(command_keys, parts[2]) or #parts == 3 then
    local obj = commands[parts[2]]
    if obj then
      return get_options(vim.tbl_keys(obj))
    end
  end
end

function M.command(object, action, ...)
  if not object or not action then
    util.err_message "Missing arguments"
    return
  end
  local command = commands[object] and commands[object][action]
  if command then
    command.handler(...)
  else
    util.err_message "Unknown command"
  end
end

return M
