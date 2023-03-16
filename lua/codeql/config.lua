local M = {}

-- user configurable options
M.defaults = {
  additional_packs = {},
  max_ram = nil,
  job_timeout = 15000,
  format_on_save = false,
  results = {
    max_paths = 4,
    max_path_depth = nil,
  },
  panel = {
    widh = 50,
    pos = "botright",
    show_filename = true,
    long_filename = false,
    group_by = "sink",
    context_lines = 3,
  },
  mappings = {
    run_query = { modes = { "n" }, lhs = "<space>qr", desc = "run query" },
    quick_eval = { modes = { "x", "n" }, lhs = "<space>qe", desc = "quick evaluate" },
    quick_eval_predicate = { modes = { "n" }, lhs = "<space>qp", desc = "quick evaluate enclosing predicate" },
  },
}

M._config = M.defaults

-- internal options
M.database = {}
M.ram_opts = {}
M.sarif = {}

function M.get_config()
  return M._config
end

function M.setup(opts)
  M._config = vim.tbl_extend("force", M.defaults, opts)
end

return M
