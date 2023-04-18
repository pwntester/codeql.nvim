local util = require "codeql.util"
local vim = vim

local M = {}

M.cache = {
  definitions = {},
  references = {},
}

local function add_to_cache(kind, fname, lnum, range, location)
  local key = string.format("%s::%d", fname, lnum)
  local entry = M.cache[kind][key]
  if not entry then
    entry = {}
  end
  entry[range] = location
  M.cache[kind][key] = entry
end

function M.process_refs(results_path)
  M.process("references", results_path)
end

function M.process_defs(results_path)
  M.process("definitions", results_path)
end

function M.process(kind, results_path)
  -- no results available, exiting
  if not util.is_file(results_path) then
    return
  end

  util.message(string.format("Processing %s", kind))
  local results = util.read_json_file(results_path)

  -- no results, exiting
  if not results or vim.tbl_count(results) == 0 then
    return
  end

  local tuples = results["#select"]["tuples"]

  --clear_path_from_cache(path)

  for _, tuple in ipairs(tuples) do
    local src = tuple[1]
    local dst = tuple[2]

    local src_fname = util.uri_to_fname(src["url"]["uri"])
    local src_lnum = src["url"]["startLine"]
    local src_range = { src["url"]["startColumn"], src["url"]["endColumn"] }
    local src_label = src["label"]

    local dst_fname = util.uri_to_fname(dst["url"]["uri"])
    local dst_lnum = dst["url"]["startLine"]
    local dst_range = { dst["url"]["startColumn"], dst["url"]["endColumn"] }
    local dst_label = dst["label"]

    if kind == "definitions" then
      add_to_cache(kind, src_fname, src_lnum, src_range, {
        fname = dst_fname,
        lnum = dst_lnum,
        range = dst_range,
        label = dst_label,
      })
    elseif kind == "references" then
      add_to_cache(kind, dst_fname, dst_lnum, dst_range, {
        fname = src_fname,
        lnum = src_lnum,
        range = src_range,
        label = src_label,
      })
    end
  end
end

function M.find_at_cursor(kind)
  if not M.cache then
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local winid = vim.api.nvim_get_current_win()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local _, row, col = unpack(vim.fn.getpos ".")
  if not vim.startswith(bufname, "ql:/") then
    return
  end
  local prefix = vim.split(bufname, "://")[1]
  local fname = vim.split(bufname, "://")[2]
  local word_at_cursor = ""

  local key = string.format("/%s::%d", fname, row)
  local entry = M.cache[kind][key]
  if not entry or vim.tbl_count(entry) == 0 then
    util.message(string.format("Cannot find %s for %s", kind, key))
    return
  end

  local matching_locs = {}
  for range, location in pairs(entry) do
    if col >= range[1] and col <= range[2] then
      table.insert(matching_locs, location)
    end
  end

  if #matching_locs == 0 then
    util.message(string.format("Cannot find matching %s for %s", kind, word_at_cursor))
    return
  elseif #matching_locs == 1 then
    -- jump to location (def/ref)
    local location = matching_locs[1]

    -- mark current position so it can be jumped back to
    vim.api.nvim_command "mark '"

    -- push a new item into tagstack
    local from = { bufnr, vim.fn.line ".", vim.fn.col ".", 0 }
    local items = { { tagname = vim.fn.expand "<cword>", from = from } }
    vim.fn.settagstack(vim.fn.win_getid(), { items = items }, "t")

    local def_bufname = string.format("ql://%s", string.sub(location.fname, 2))
    local opts = {
      line = location.lnum,
      target_winid = winid
    }
    if vim.fn.bufnr(def_bufname) > -1 then
      vim.api.nvim_command(string.format("buffer %s", def_bufname))
      if opts.line then
        util.jump_to_line(opts)
      end
    else
      local def_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(def_bufnr, def_bufname)
      local path = string.sub(location.fname, 2)
      util.open_from_archive(def_bufnr, path, opts)
    end
  elseif #matching_locs > 1 then
    local items = {}
    for _, location in ipairs(matching_locs) do
      local rel_fname = string.sub(location.fname, 2)
      table.insert(items, {
        filename = string.format("%s://%s", prefix, rel_fname),
        module = location.fname,
        lnum = location.lnum,
        col = location.range[1],
        text = location.label,
      })
    end

    vim.fn.setqflist({}, " ", {
      title = string.format("CodeQL %s", kind),
      items = items,
    })
    vim.api.nvim_command "botright copen"
  end
end

return M
