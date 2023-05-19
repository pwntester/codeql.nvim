local NuiTree = require "nui.tree"
local NuiLine = require "nui.line"
local Split = require "nui.split"
local util = require "codeql.util"
local loader = require "codeql.loader"
local cli = require "codeql.cliserver"
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local entry_display = require "telescope.pickers.entry_display"
local vim = vim

local M = {}

-- type RunStatus struct {
-- 	Id            int    `json:"id"`
-- 	Query         string `json:"query"`
-- 	Status        string `json:"status"`
-- 	FailureReason string `json:"failure_reason"`
-- }
--
-- type RepoWithFindings struct {
-- 	Nwo   string `json:"nwo"`
-- 	Count int    `json:"count"`
-- 	RunId int    `json:"run_id"`
-- }
-- type Results struct {
-- 	Runs                                   []RunStatus        `json:"runs"`
-- 	ResositoriesWithFindings               []RepoWithFindings `json:"repositories_with_findings"`
-- 	TotalFindingsCount                     int                `json:"total_findings_count"`
-- 	TotalSuccessfulScans                   int                `json:"total_successful_scans"`
-- 	TotalFailedScans                       int                `json:"total_failed_scans"`
-- 	TotalRepositoriesWithFindings          int                `json:"total_repositories_with_findings"`
-- 	TotalSkippedRepositories               int                `json:"total_skipped_repositories"`
-- 	TotalSkippedAccessMismatchRepositories int                `json:"total_skipped_access_mismatch_repositories"`
-- 	TotalSkippedNotFoundRepositories       int                `json:"total_skipped_not_found_repositories"`
-- 	TotalSkippedNoDatabaseRepositories     int                `json:"total_skipped_no_database_repositories"`
-- 	TotalSkippedOverLimitRepositories      int                `json:"total_skipped_over_limit_repositories"`
-- }

M.load = function(name)
  -- yep, self-CMDi, yay!
  local json = vim.fn.system("gh mrva status --json --session " .. name)
  local status, err = util.json_decode(json)
  if err then
    vim.notify(err, 2)
    return
  end

  if status.total_repositories_with_findings == 0 then
    vim.notify("No findings found", 2)
    return
  end

  local nodes = {}

  -- add title node
  table.insert(nodes, NuiTree.Node({ type = "label", label = "MRVA Results - " .. name }))

  -- total finding count
  table.insert(nodes, NuiTree.Node({ type = "label", label = "Findings: " .. status.total_findings_count }))

  -- sort by stars
  table.sort(status.repositories_with_findings, function(a, b)
    return a.stars > b.stars
  end)

  for _, item in ipairs(status.repositories_with_findings) do
    table.insert(nodes, NuiTree.Node({
      type = "result",
      nwo = item.nwo,
      name = name,
      count = item.count,
      stars = item.stars,
    }))
  end

  local split = Split {
    relative = "win",
    position = "left",
    size = 50,
    win_options = {
      number = false,
      relativenumber = false,
      wrap = false,
      winhighlight = "Normal:NormalAlt",
    },
    buf_options = {
      bufhidden = "delete",
      buftype = "nowrite",
      modifiable = false,
      swapfile = false,
      filetype = "codeql_mrva",
    },
  }
  split:mount()

  local tree = NuiTree {
    winid = split.winid,
    nodes = nodes,
    prepare_node = function(node)
      local line = NuiLine()
      if node.type == "label" then
        line:append(node.label, "Comment")
      end
      if node.type == "result" then
        --line:append("  ")
        --line:append("", "SpecialKey")
        --line:append(" ")
        line:append(node.nwo, "Normal")
        line:append(" ")
        line:append("💥 " .. tostring(node.count), "Comment")
        line:append(" ")
        line:append("✨ " .. tostring(node.stars), "Comment")
      end
      return line
    end
  }

  local map_options = { noremap = true, nowait = true }

  split:map("n", "q", function()
    split:unmount()
  end, { noremap = true })

  split:map("n", "<CR>", function()
    local node = tree:get_node()
    if node.type == "result" then
      local tmpdir = vim.fn.fnamemodify(vim.fn.tempname(), ":p:h")
      local sarif_filename = node.nwo:gsub("/", "_") .. ".sarif"
      local bqrs_filename = node.nwo:gsub("/", "_") .. ".bqrs"
      local json_filename = node.nwo:gsub("/", "_") .. ".json"
      -- check if file exists
      if vim.fn.filereadable(tmpdir .. "/" .. sarif_filename) == 0 and vim.fn.filereadable(tmpdir .. "/" .. bqrs_filename) == 0 then
        vim.fn.system("gh mrva download --session " .. node.name .. " --nwo " .. node.nwo .. " --output-dir " .. tmpdir)
      end
      if vim.fn.filereadable(tmpdir .. "/" .. sarif_filename) > 0 then
        loader.load_sarif_results(tmpdir .. "/" .. sarif_filename)
      elseif vim.fn.filereadable(tmpdir .. "/" .. bqrs_filename) > 0 then
        local cmd = {
          "bqrs",
          "decode",
          "-v",
          "--log-to-stderr",
          "-o=" .. tmpdir .. "/" .. json_filename,
          "--format=json",
          "--entities=string,url",
          tmpdir .. "/" .. bqrs_filename,
        }
        cli.runAsync(
          cmd,
          vim.schedule_wrap(function(_)
            if util.is_file(tmpdir .. "/" .. json_filename) then
              loader.load_raw_results(tmpdir .. "/" .. json_filename)
            else
              util.err_message("Error: Cant find raw results at " .. tmpdir .. "/" .. json_filename)
            end
          end)
        )
      end
    end
  end, map_options)

  tree:render()
  vim.api.nvim_buf_set_option(tree.bufnr, "filetype", "codeql_mrva")
end

local function gen_from_gh_mrva_list()
  local make_display = function(entry)
    if not entry then
      return nil
    end
    local date = vim.split(entry.session.timestamp, "T", true)[1]
    local rest = vim.split(entry.session.timestamp, "T", true)[2]
    local time = vim.split(rest, ".", true)[1]
    local datetime = date .. " " .. time

    local columns = {
      { datetime },
      { entry.session.language },
      { entry.session.repository_count },
      { entry.session.name,            "TelescopeResultsNumber" },
    }

    local displayer = entry_display.create {
      separator = "",
      items = {
        { width = 25 },
        { width = 10 },
        { width = 5 },
        { remaining = true },
      },
    }

    return displayer(columns)
  end

  return function(session)
    if not session or vim.tbl_isempty(session) then
      return nil
    end

    return {
      value = session.name,
      ordinal = session.name .. " " .. session.timestamp,
      display = make_display,
      session = session,
    }
  end
end

function M.list_sessions()
  local json_str = vim.fn.system("gh mrva list --json | jq '. |= sort_by(.timestamp)'")
  local sessions = vim.fn.json_decode(json_str)
  pickers.new({}, {
    prompt_title = "MRVA session",
    finder = finders.new_table {
      results = sessions,
      entry_maker = gen_from_gh_mrva_list(),
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        M.load(selection.value)
      end)
      return true
    end,
  }):find()
end

return M
