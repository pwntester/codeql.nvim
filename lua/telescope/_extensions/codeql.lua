local pickers = require "telescope.pickers"
local sorters = require "telescope.sorters"
local finders = require "telescope.finders"
local utils = require "telescope.utils"
local putils = require "telescope.previewers.utils"
local previewers = require "telescope.previewers"
local defaulter = utils.make_default_callable
local Path = require "plenary.path"
local pfiletype = require "plenary.filetype"
local ns_previewer = vim.api.nvim_create_namespace "telescope.previewers"
local util = require "codeql.util"
local actions = require "telescope.actions"
local action_set = require "telescope.actions.set"
local action_state = require "telescope.actions.state"

local lookup_keys = {
  value = 1,
  ordinal = 1,
}

-- Gets called only once to parse everything out for the ugrep, after that looks up directly.
local parse = function(t)
  -- {opt/src/pom.xml}:5: distributed with this work for additional information
  local _, _, filename, lnum, text = string.find(t.value, [[{([^:]+)}:(%d+):(.*)]])

  local ok
  ok, lnum = pcall(tonumber, lnum)
  if not ok then
    lnum = nil
  end

  t.filename = filename
  t.lnum = lnum
  t.text = text

  return { filename, lnum, text }
end

--- Special options:
---  - disable_coordinates: Don't show the line & row numbers
---  - only_sort_text: Only sort via the text. Ignore filename and other items
local function gen_from_vimgrep(opts)
  local mt_vimgrep_entry

  opts = opts or {}

  local disable_devicons = opts.disable_devicons
  local disable_coordinates = opts.disable_coordinates
  local only_sort_text = opts.only_sort_text

  local execute_keys = {
    path = function(t)
      if Path:new(t.filename):is_absolute() then
        return t.filename, false
      else
        return Path:new({ t.cwd, t.filename }):absolute(), false
      end
    end,

    filename = function(t)
      return parse(t)[1], true
    end,

    lnum = function(t)
      return parse(t)[2], true
    end,

    text = function(t)
      return parse(t)[3], true
    end,
  }

  -- For text search only, the ordinal value is actually the text.
  if only_sort_text then
    execute_keys.ordinal = function(t)
      return t.text
    end
  end

  local display_string = "%s:%s%s"

  mt_vimgrep_entry = {
    cwd = vim.fn.expand(opts.cwd or vim.loop.cwd()),

    display = function(entry)
      local display_filename = utils.transform_path(opts, entry.filename)

      local coordinates = ""
      if not disable_coordinates then
        coordinates = string.format("%s", entry.lnum)
      end

      local display, hl_group = utils.transform_devicons(
        entry.filename,
        string.format(display_string, display_filename, coordinates, entry.text),
        disable_devicons
      )

      if hl_group then
        return display, { { { 1, 3 }, hl_group } }
      else
        return display
      end
    end,

    __index = function(t, k)
      local raw = rawget(mt_vimgrep_entry, k)
      if raw then
        return raw
      end

      local executor = rawget(execute_keys, k)
      if executor then
        local val, save = executor(t)
        if save then
          rawset(t, k, val)
        end
        return val
      end

      return rawget(t, rawget(lookup_keys, k))
    end,
  }

  return function(line)
    return setmetatable({ line }, mt_vimgrep_entry)
  end
end

local cmd_generator = function(prompt)
  if not prompt or prompt == "" then
    return nil
  end
  local args = {
    "ugrep",
    "--decompress",
    "--color=never",
    "--no-heading",
    "--line-number",
    "--smart-case",
    prompt,
    vim.g.codeql_database.sourceArchiveZip,
  }

  local cmd = vim.tbl_flatten { args }
  return cmd
end

local jump_to_line = function(self, bufnr, lnum)
  if lnum and lnum > 0 then
    pcall(vim.api.nvim_buf_add_highlight, bufnr, ns_previewer, "TelescopePreviewLine", lnum - 1, 0, -1)
    pcall(vim.api.nvim_win_set_cursor, self.state.winid, { lnum, 0 })
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd "norm! zz"
    end)
  end

  self.state.last_set_bufnr = bufnr
end

local zip_grep_previewer = defaulter(function()
  return previewers.new_buffer_previewer {
    title = "",
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,

    define_preview = function(self, entry)
      putils.job_maker({ "unzip", "-p", vim.g.codeql_database.sourceArchiveZip, entry.filename }, self.state.bufnr, {
        value = entry.value,
        bufname = self.state.bufname,
        callback = function(bufnr)
          jump_to_line(self, bufnr, entry.lnum)
        end,
      })
      local ft = pfiletype.detect(entry.filename)
      putils.highlighter(self.state.bufnr, ft)
    end,
  }
end)

local live_zip_grep = function(opts)
  opts = opts or {}

  local db = vim.g.codeql_database
  if not db then
    util.err_message "Missing database. Use :SetDatabase command"
    return
  end

  opts.entry_maker = gen_from_vimgrep(opts)
  opts.cwd = opts.cwd and vim.fn.expand(opts.cwd)

  pickers.new(opts, {
    prompt_title = "",
    finder = finders.new_job(cmd_generator, opts.entry_maker, opts.max_results, opts.cwd),
    previewer = zip_grep_previewer.new(opts),
    sorter = sorters.highlighter_only(opts),
    attach_mappings = function()
      action_set.select:replace(function(prompt_bufnr)
        local entry = action_state.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)
        util.open_from_archive(vim.g.codeql_database.sourceArchiveZip, entry.filename)
      end)
      return true
    end,
  }):find()
end

-- return require("telescope").register_extension {
--   exports = { live_zip_grep = live_zip_grep },
-- }

return live_zip_grep
