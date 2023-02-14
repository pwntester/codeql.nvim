local util = require "codeql.util"

local history = {}

-- exported functions

local M = {}

function M.save_bqrs(bqrs_path, query_path, db_path, kind, id, count, bufnr)
  -- should we store quickEval results?
  local entry = {
    bufnr = bufnr,
    bqrs = bqrs_path,
    query = query_path,
    database = db_path,
    epoch = vim.fn.localtime(),
    time = vim.fn.strftime "%c",
    kind = kind,
    id = id,
    count = count,
  }
  table.insert(history, entry)
end

function M.menu()
  vim.api.nvim_command "redraw"
  local options = { "Select:" }
  for i, entry in ipairs(history) do
    if util.is_file(entry.bqrs) then
      local entry_text = i
        .. ". "
        .. vim.fn.fnamemodify(entry.query, ":t")
        .. " ("
        .. entry.count
        .. " results) ("
        .. entry.time
        .. ") "
        .. entry.database
      table.insert(options, entry_text)
    end
  end
  local choice = vim.fn.inputlist(options)
  if choice < 1 or choice > #history then
    return
  elseif choice < 1 + #history then
    local entry = history[choice]
    if entry then
      util.bqrs_info({
        bqrs_path = entry.bqrs,
        bufnr = entry.bufnr,
        db_path = entry.database,
        query_path = entry.query,
        query_kind = entry.kind,
        query_id = entry.id,
        save_bqrs = false,
      }, require("codeql.loader").process_results)
    end
  end
end

return M
