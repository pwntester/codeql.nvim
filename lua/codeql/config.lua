local M = {}

-- user configurable options
M.defaults = {
  search_path = {},
  max_ram = nil,
  format_on_save = false,
  results = {
    max_paths = 4,
    max_path_depth = nil,
  },
  panel = {
    show_filename = true,
    long_filename = false,
    group_by = "sink",
  },
}

M._config = M.defaults

-- internal options
M.database = {}
M.ram_opts = {}
M.sarif_path = nil -- only set when SARIF file contains source code

function M.get_config()
  return M._config
end

function M.setup(opts)
  M._config = vim.tbl_extend("force", M.defaults, opts)
end

return M
