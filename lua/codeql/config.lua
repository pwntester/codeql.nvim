local M = {}

M.values = {}
M.database = {}
M.ram_opts = {}
M.sarif = {}

function M.setup(opts)
  -- user configurable options
  local defaults = {
    additional_packs = {},
    max_ram = nil,
    job_timeout = 15000,
    format_on_save = false,
    -- Command returning list of CodeQL databases (eg: { "gh", "qldb", "list" })
    find_databases_cmd = nil,
    -- Telescope entry maker for the list of databases
    database_list_entry_maker = nil,
    results = {
      max_paths = 4,
      max_path_depth = nil,
    },
    panel = {
      width = 50,
      pos = "botright",
      show_filename = true,
      long_filename = false,
      group_by = "sink",
      context_lines = 5,
      alignment = "left"
    },
    mappings = {
      run_query = { modes = { "n" }, lhs = "<space>qr", desc = "run query" },
      quick_eval = { modes = { "x", "n" }, lhs = "<space>qe", desc = "quick evaluate" },
      quick_eval_predicate = { modes = { "n" }, lhs = "<space>qp", desc = "quick evaluate enclosing predicate" },
    },
  }
  local util = require("codeql.util")
  M.values = util.tableMerge(defaults, opts)
end

return M
