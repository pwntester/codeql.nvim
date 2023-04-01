local NuiTree = require "nui.tree"
local NuiLine = require "nui.line"
local Split = require "nui.split"
local util = require "codeql.util"
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

M.draw = function(name)
  local json = vim.fn.system("gh mrva status --json --name " .. name)
  local status, err = util.json_decode(json)
  if err then
    vim.notify(err, 2)
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
        line:append("  ")
        line:append("", "SpecialKey")
        line:append(" ")
        line:append(node.nwo, "String")
        line:append(" ")
        line:append(tostring(node.count) .. " 💥", "Comment")
        line:append(" ")
        line:append(tostring(node.stars).. " ✨", "Comment")
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
      vim.fn.system("gh mrva download --name " .. node.name .. " --nwo " .. node.nwo .. " --output-dir " .. tmpdir)
      vim.api.nvim_command("LoadSarif " .. tmpdir .. "/" .. node.nwo:gsub("/", "_") .. ".sarif")
      return
    end
  end, map_options)

  tree:render()
  vim.api.nvim_buf_set_option(tree.bufnr, "filetype", "codeql_mrva")
end

return M
