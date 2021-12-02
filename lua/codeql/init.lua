local util = require "codeql.util"
local queryserver = require "codeql.queryserver"
local vim = vim
local api = vim.api
local format = string.format
local ts_utils = require "nvim-treesitter.ts_utils"

local M = {}

vim.g.codeql_database = {}
vim.g.codeql_ram_opts = {}

M.count = 0

function M.load_definitions()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.fn.bufname(bufnr)

  -- not a codeql:// buffer
  if not vim.startswith(bufname, "codeql:/") then
    return
  end

  -- check if file has already been processed
  local defs = require "codeql.defs"
  local fname = vim.split(bufname, ":")[2]
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
  local database = vim.fn.fnamemodify(vim.trim(dbpath), ":p")
  if not vim.endswith(database, "/") then
    database = database .. "/"
  end
  if not util.is_dir(database) then
    util.err_message("Incorrect database: " .. database)
  else
    local metadata = util.database_info(database)
    metadata.path = database
    api.nvim_set_var("codeql_database", metadata)
    queryserver.register_database()
    util.message("Database set to " .. database)
  end
  --TODO: print(util.database_upgrades(vim.g.codeql_database.dbscheme))
  vim.g.codeql_ram_opts = util.resolve_ram(true)
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
  local node = ts_utils.get_node_at_cursor()
  print(vim.inspect(node:type()))
  if not node then
    vim.notify("No treesitter CodeQL parser installed", 2)
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
  local db = vim.g.codeql_database
  if not db then
    util.err_message "Missing database. Use :SetDatabase command"
    return
  end

  local dbPath = vim.g.codeql_database.path
  local queryPath = vim.fn.expand "%:p"

  local libPaths = util.resolve_library_path(queryPath)
  if not libPaths then
    util.err_message "Could not resolve library paths"
    return
  end

  local opts = {
    quick_eval = quick_eval,
    bufnr = api.nvim_get_current_buf(),
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
  c = "cpp/ql/src/%s.ql",
  cpp = "cpp/ql/src/%s.ql",
  java = "java/ql/src/%s.ql",
  cs = "csharp/ql/src/%s.ql",
  go = "ql/src/%s.ql",
  javascript = "javascript/ql/src/%s.ql",
  python = "python/ql/src/%s.ql",
  ruby = "ql/src/ide-contextual-queries/%s.ql",
}

function M.run_print_ast()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.fn.bufname(bufnr)

  -- not a codeql:// buffer
  if not vim.startswith(bufname, "codeql:/") then
    return
  end

  local fname = vim.split(bufname, ":")[2]
  M.run_templated_query("printAst", fname)
end

function M.run_templated_query(query_name, param)
  local bufnr = api.nvim_get_current_buf()
  local dbPath = vim.g.codeql_database.path
  local ft = vim.bo[bufnr]["ft"]
  if not templated_queries[ft] then
    --util.err_message(format('%s does not support %s file type', query_name, ft))
    return
  end
  local query = format(templated_queries[ft], query_name)
  local queryPath
  for _, path in ipairs(vim.g.codeql_search_path) do
    local candidate = format("%s/%s", path, query)
    if util.is_file(candidate) then
      queryPath = candidate
      break
    end
  end
  if not queryPath then
    --vim.notify(format('Cannot find a valid %s query', query_name), 2)
    return
  end

  local templateValues = {
    selectedSourceFile = {
      values = {
        tuples = { { { stringValue = param } } },
      },
    },
  }
  local libPaths = util.resolve_library_path(queryPath)
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
end

function M.grep_source()
  local ok = require("telescope").load_extension "zip_grep"
  if ok then
    local db = vim.g.codeql_database
    if not db then
      util.err_message "Missing database. Use :SetDatabase command"
      return
    else
      require("telescope").extensions.zip_grep.zip_grep {
        archive = vim.g.codeql_database.sourceArchiveZip,
      }
    end
  end
end

return M
