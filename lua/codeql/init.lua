local util = require'codeql.util'
local queryserver = require'codeql.queryserver'
local vim = vim
local api = vim.api

local M = {}

function M.set_database(dbpath)
  local database = vim.fn.fnamemodify(vim.trim(dbpath), ':p')
  if not util.is_dir(database) then
    util.err_message('Incorrect database: '..database)
    return nil
  else
    api.nvim_buf_set_var(0, 'codeql_database', database)
    util.message('Database set to '..database)
  end
end

function M.get_database()
  local status, database = pcall(api.nvim_buf_get_var, 0, 'codeql_database')
  if not vim.endswith(database, '/') then
    database = database..'/'
  end
  return status and database or nil
end

function M.run_query(quick_eval)
  local dbPath = M.get_database()
  if dbPath == nil then
    util.err_message('Missing database. Use SetDatabase command')
    return nil
  end

  if not util.is_dir(dbPath..'/src') and util.is_file(dbPath..'/src.zip') then
    util.run_cmd('mkdir '..dbPath..'/src')
    util.run_cmd('unzip '..dbPath..'/src.zip -d '..dbPath..'/src')
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
    metadata = util.extract_query_metadata(queryPath);
    libraryPath = libPaths.libraryPath;
    dbschemePath = libPaths.dbscheme;
  }
  print(vim.inspect(opts))
  queryserver.run_query(opts)
end

return M
