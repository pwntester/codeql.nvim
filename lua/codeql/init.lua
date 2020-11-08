local util = require'codeql.util'
local queryserver = require'codeql.queryserver'
local vim = vim
local api = vim.api
local format = string.format

local M = {}

vim.g.codeql_database = {}
vim.g.codeql_ram_opts = {}

function M.set_database(dbpath)
  local database = vim.fn.fnamemodify(vim.trim(dbpath), ':p')
  if not vim.endswith(database, '/') then
    database = database..'/'
  end
  if not util.is_dir(database) then
    util.err_message('Incorrect database: '..database)
  else
    local metadata = util.database_info(database)
    metadata.path = database
    api.nvim_set_var('codeql_database', metadata)
    util.message('Database set to '..database)
  end
  --TODO: print(util.database_upgrades(vim.g.codeql_database.dbscheme))
  vim.g.codeql_ram_opts = util.resolve_ram(true)
end

function M.run_query(quick_eval)
  local dbPath = vim.g.codeql_database.path
  if dbPath == nil then
    util.err_message('Missing database. Use SetDatabase command')
    return nil
  end

  local queryPath = vim.fn.expand('%:p')

  -- [bufnum, lnum, col, off, curswant]
  local line_start, column_start, line_end, column_end

  if vim.fn.getpos("'<")[2] == vim.fn.getcurpos()[2] and
    vim.fn.getpos("'<")[3] == vim.fn.getcurpos()[3] then
    line_start = vim.fn.getpos("'<")[2]
    column_start = vim.fn.getpos("'<")[3]
    line_end = vim.fn.getpos("'>")[2]
    column_end = vim.fn.getpos("'>")[3]

    column_end = column_end == 2147483647 and 1 + vim.fn.len(vim.fn.getline(line_end)) or 1 + column_end
  else
    line_start = vim.fn.getcurpos()[2]
    column_start = vim.fn.getcurpos()[3]
    line_end = vim.fn.getcurpos()[2]
    column_end = vim.fn.getcurpos()[3]
  end

  local libPaths = util.resolve_library_path(queryPath)

  local opts = {
    quick_eval = quick_eval;
    buf = api.nvim_get_current_buf();
    query = queryPath;
    dbPath = dbPath;
    startLine = line_start;
    startColumn = column_start;
    endLine = line_end;
    endColumn = column_end;
    metadata = util.query_info(queryPath);
    libraryPath = libPaths.libraryPath;
    dbschemePath = libPaths.dbscheme;
  }

  queryserver.run_query(opts)
end

local templated_queries = {
  c          = 'cpp/ql/src/%s.ql';
  cpp        = 'cpp/ql/src/%s.ql';
  java       = 'java/ql/src/%s.ql';
  cs         = 'chsarp/ql/src/%s.ql';
  go         = 'ql/src/%s.ql';
  javascript = 'javascript/ql/src/%s.ql';
  python     = 'python/ql/src/%s.ql';
}

function M.run_templated_query(query_name)
  local bufnr = api.nvim_get_current_buf()
  M.ast_current_bufnr = bufnr
  local dbPath = vim.g.codeql_database.path
  local bufname = vim.fn.expand('%:p')
  if not dbPath or not vim.startswith(bufname, 'zipfile:') then
    util.err_message('Missing database or incorrect code buffer')
    return
  end
  local filePath = '/'..vim.split(bufname, '::')[2]
  local ft = vim.bo[bufnr]['ft']
  if not templated_queries[ft] then
    util.err_message(format('%s does not support %s file type', query_name, ft))
    return
  end
  local query = format(templated_queries[ft], query_name)
  local queryPath
  for _, path in ipairs(vim.g.codeql_search_path) do
    local candidate = format('%s/%s', path, query)
    if util.is_file(candidate) then
      queryPath = candidate
      break
    end
  end
  if not queryPath then
    util.err_message(format('Cannot find a valid %s query', query_name))
    return
  end

  local templateValues = {
    selectedSourceFile = {
      values = {
        tuples = { { { stringValue = filePath; } } }
        }
      }
  }
  local libPaths = util.resolve_library_path(queryPath)
  local opts = {
    quick_eval = false;
    buf = api.nvim_get_current_buf();
    query = queryPath;
    dbPath = dbPath;
    metadata = util.query_info(queryPath);
    libraryPath = libPaths.libraryPath;
    dbschemePath = libPaths.dbscheme;
    templateValues = templateValues;
  }
  require'codeql.queryserver'.run_query(opts)
end

return M
