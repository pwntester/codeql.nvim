local util = require'codeql.util'
local uri_to_fname = require'codeql.loader'.uri_to_fname
local format = string.format
local api = vim.api

local M = {}

M.cache = {
  definitions = {};
  references = {};
}
M.processedFiles = {}

local function tbl_filter_by_key(tbl, func)
  local new_tbl = {}
  for k, v in pairs(tbl) do
    if func(k, v) then new_tbl[k] = v end
  end
  return new_tbl
end

local function add_to_cache(kind, fname, lnum, range, location)
  local key = format('%s::%d', fname, lnum)
  local entry = M.cache[kind][key]
  if not entry then entry = {} end
  entry[range] = location
  M.cache[kind][key] = entry
end

-- local function clear_path_from_cache(path)
--   local clear_fn = function(k, _)
--     if not vim.startswith(k, path..'::') then
--       return true
--     else
--       return false
--     end
--   end
--   tbl_filter_by_key(M.cache.definitions, clear_fn)
--   tbl_filter_by_key(M.cache.references, clear_fn)
--   M.processedFiles[path] = false
-- end

function M.process_refs(results_path)
  M.process('references', results_path)
end

function M.process_defs(results_path)
  M.process('definitions', results_path)
end

function M.process(kind, results_path)

  -- no results available, exiting
  if not util.is_file(results_path) then return end

  util.message(format('Processing %s from %s', kind, results_path))
  util.message('')
  local results = util.read_json_file(results_path)

  -- no results, exiting
  if not results or vim.tbl_count(results) == 0 then return end

  local tuples = results['#select']['tuples']

  --clear_path_from_cache(path)

  for _, tuple in ipairs(tuples) do
    local src = tuple[1]
    local dst = tuple[2]

    local src_fname = uri_to_fname(src['url']['uri'])
    local src_lnum = src['url']['startLine']
    local src_range = {src['url']['startColumn'], src['url']['endColumn']}
    local src_label = src['label']

    local dst_fname = uri_to_fname(dst['url']['uri'])
    local dst_lnum = dst['url']['startLine']
    local dst_range = {dst['url']['startColumn'], dst['url']['endColumn']}
    local dst_label = dst['label']

    if kind == 'definitions' then
      add_to_cache(kind, src_fname, src_lnum, src_range, {
        fname = dst_fname;
        lnum = dst_lnum;
        range = dst_range;
        label = dst_label;
      })
    elseif kind == 'references' then
      add_to_cache(kind, dst_fname, dst_lnum, dst_range, {
        fname = src_fname;
        lnum = src_lnum;
        range = src_range;
        label = src_label;
      })
    end
  end

end

function M.find_at_cursor(kind)
  if not M.cache then return end
  local bufnr = api.nvim_get_current_buf()
  local bufname = vim.fn.bufname(bufnr)
  local _, row, col = unpack(vim.fn.getpos('.'))
  if not vim.startswith(bufname, 'codeql:/') then return end
  local prefix = vim.split(bufname, '::')[1]
  local fname = format('/%s', vim.split(bufname, '::')[2])
  local word_at_cursor = ''

  local key = format('%s::%d', fname, row)

  local entry = M.cache[kind][key]
  if not entry or vim.tbl_count(entry) == 0 then return end

  local matching_locs = {}
  for range, location in pairs(entry) do
    if col >= range[1] and col <= range[2] then
      table.insert(matching_locs, location)
    end
  end

  if #matching_locs == 0 then
    util.message(format('Didnt found matching %s for %s', kind, word_at_cursor))

  elseif #matching_locs == 1 then

    -- jump to location (def/ref)
    local location = matching_locs[1]
    local archive_fname = format('%s::%s', prefix, string.sub(location.fname, 2))

    -- mark current position so it can be jumped back to
    api.nvim_command("mark '")

    -- push a new item into tagstack
    local from = {bufnr, vim.fn.line('.'), vim.fn.col('.'), 0}
    local items = {{tagname=vim.fn.expand('<cword>'), from=from}}
    vim.fn.settagstack(vim.fn.win_getid(), {items=items}, 't')

    api.nvim_command(format('e %s', archive_fname))
    api.nvim_win_set_cursor(0, {location.lnum, location.range[1]})

  elseif #matching_locs > 1 then
    local items = {}
    for _, location in ipairs(matching_locs) do
      local rel_fname = string.sub(location.fname, 2)
      table.insert(items, {
        filename = format('%s::%s', prefix, rel_fname);
        module = location.fname;
        lnum = location.lnum;
        col = location.range[1];
        text = location.label;
      })
    end

    vim.fn.setqflist({}, ' ', {
      title = format('CodeQL %s', kind);
      items = items;
    })
    api.nvim_command("botright copen")
  end
end

return M
