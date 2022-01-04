local M = {}

-- user configurable options
M.defaults = {
  max_ram = -1,
  panel_longnames = false,
  panel_filename = true,
  group_by_sink = false,
  path_max_length = -1,
  search_path = {},
  fmt_onsave = false,
}

M._config = M.defaults

-- internal options
M.database = {}
M.ram_opts = {}

function M.get_config()
  return M._config
end

function M.setup(opts)
  M._config = vim.tbl_extend("force", M.defaults, opts)
end

return M
