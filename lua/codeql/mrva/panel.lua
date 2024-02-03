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
-- 	QueryId       string `json:"query_id"`
-- 	Status        string `json:"status"`
-- 	FailureReason string `json:"failure_reason"`
-- }
--
-- type RepoWithFindings struct {
-- 	Nwo   string `json:"nwo"`
-- 	Count int    `json:"count"`
-- 	RunId int    `json:"run_id"`
-- 	Query         string `json:"query"`
-- 	QueryId       string `json:"query_id"`
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
  local statuses, err = util.json_decode(json)
  if err then
    vim.notify(err, 2)
    return
  end

  if #statuses == 0 or statuses == nil then
    vim.notify("No results found", 2)
    return
  end

  local status = statuses[1]
  if status.total_repositories_with_findings == 0 then
    vim.notify("No findings found", 2)
    return
  end

  local nodes = {}

  -- add title node
  table.insert(nodes, NuiTree.Node { type = "label", label = "MRVA Results - " .. name })

  -- total finding count
  table.insert(nodes, NuiTree.Node { type = "label", label = "Findings: " .. status.total_findings_count })

  -- group by query_id
  local query_ids = {}
  for _, item in ipairs(status.repositories_with_findings) do
    if query_ids[item.query_id] == nil then
      query_ids[item.query_id] = { item }
    else
      table.insert(query_ids[item.query_id], item)
    end
  end

  for query_id, item_list in pairs(query_ids) do
    -- sort by stars
    table.sort(item_list, function(a, b)
      return a.stars > b.stars
    end)

    -- children of query_id
    local children = {}
    for _, item in ipairs(item_list) do
      table.insert(
        children,
        NuiTree.Node {
          type = "result",
          nwo = item.nwo,
          name = name,
          query_id = item.query_id,
          run_id = item.run_id,
          count = item.count,
          stars = item.stars,
        }
      )
    end

    -- add heading
    table.insert(nodes, NuiTree.Node({ type = "label", label = query_id }, children))
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
        if node:has_children() then
          line:append(node:is_expanded() and " " or " ", "SpecialChar")
        end
        line:append(node.label, "Comment")
      elseif node.type == "result" then
        line:append "  - "
        line:append(node.nwo, "Normal")
        line:append " "
        line:append("💥 " .. tostring(node.count), "Comment")
        line:append " "
        line:append("✨ " .. tostring(node.stars), "Comment")
      end
      return line
    end,
  }

  -- local function check_node_health(node)
  --   local query_content = read_file(node.filepath)
  --
  --   local ok, err = pcall(vim.treesitter.query.parse_query, node.lang, query_content)
  --
  --   if ok then
  --     node.ok = true
  --     node.err = nil
  --     node.err_position = nil
  --   else
  --     node.ok = false
  --     node.err = err
  --     node.err_position = string.match(node.err, "position (%d+)")
  --   end
  -- end

  -- mappings
  local map_options = { noremap = true, nowait = true }

  -- A session can contains several runs,
  -- each run correspond to one query/query_id on several repos
  -- however, more than one run can use the same query. This is true if there is more than 1000 repos
  -- two ways of presenting results:
  -- 1. show query id at the top level and repos (stars/count) as children
  -- 2. show repos at the top level and query id as children
  -- Its common to run just one or few queries so 1. is better
  -- When clicking on a child node, we need to download the results for a single repo/run_id combo
  -- We can do that passing --run and --nwo to gh mrva download

  -- exit
  split:map("n", "q", function()
    split:unmount()
  end, map_options)

  -- refresh
  split:map("n", "r", function()
    -- local node = tree:get_node()
    vim.schedule(function()
      -- if node:has_children() then
      --   for_each(tree:get_nodes(node:get_id()), check_node_health)
      -- else
      --   check_node_health(node)
      -- end

      tree:render()
    end)
  end, map_options)

  -- collapse all
  split:map("n", "c", function()
    vim.schedule(function()
      for _, node in ipairs(tree:get_nodes()) do
        if node:has_children() and node:is_expanded() then
          node:collapse()
        end
      end
      tree:render()
    end)
  end, map_options)

  -- expand all
  split:map("n", "a", function()
    vim.schedule(function()
      for _, node in ipairs(tree:get_nodes()) do
        if node:has_children() and not node:is_expanded() then
          node:expand()
        end
      end
      tree:render()
    end)
  end, map_options)

  -- toggle expand/collapse
  split:map("n", "o", function()
    local node, linenr = tree:get_node()
    if not node:has_children() then
      node, linenr = tree:get_node(node:get_parent_id())
    end
    if node and node:is_expanded() and node:collapse() then
      vim.api.nvim_win_set_cursor(split.winid, { linenr, 0 })
      tree:render()
    elseif node and not node:is_expanded() and node:expand() then
      if not node.checked then
        node.checked = true

        vim.schedule(function()
          -- for _, n in ipairs(tree:get_nodes(node:get_id())) do
          --   check_node_health(n)
          -- end
          tree:render()
        end)
      end

      vim.api.nvim_win_set_cursor(split.winid, { linenr, 0 })
      tree:render()
    end
  end, map_options)

  -- open
  split:map("n", "<CR>", function()
    local node = tree:get_node()
    if node.type == "label" then
    elseif node.type == "result" then
      local tmpdir = vim.fn.fnamemodify(vim.fn.tempname(), ":p:h")
      local filename = node.nwo:gsub("/", "_") .. "_" .. tostring(node.run_id)
      local sarif_filename = filename .. ".sarif"
      local bqrs_filename = filename .. ".bqrs"
      local json_filename = filename .. ".json"
      -- check if file exists
      if
        vim.fn.filereadable(tmpdir .. "/" .. sarif_filename) == 0
        and vim.fn.filereadable(tmpdir .. "/" .. bqrs_filename) == 0
      then
        local cmd = "gh mrva download --run " .. node.run_id .. " --nwo " .. node.nwo .. " --output-dir " .. tmpdir
        print("Downloading results for " .. node.nwo .. " with " .. cmd)
        local output = vim.fn.system(cmd)
        output = output:gsub("\n", "")
        if string.find(output, "Please try again later") then
          util.err_message "Results are not ready yet"
          return
        end
      end
      if vim.fn.filereadable(tmpdir .. "/" .. sarif_filename) > 0 then
        print("Loading SARIF results for " .. node.nwo .. " from " .. tmpdir .. "/" .. sarif_filename)
        loader.load_sarif_results(tmpdir .. "/" .. sarif_filename)
      elseif vim.fn.filereadable(tmpdir .. "/" .. bqrs_filename) > 0 then
        print("Loading BQRS results for " .. node.nwo .. " from " .. tmpdir .. "/" .. bqrs_filename)
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
              util.err_message("Error: Can't find raw results at " .. tmpdir .. "/" .. json_filename)
              return
            end
          end)
        )
      else
        util.err_message("Error: Can't find results for " .. node.nwo)
        return
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
      { entry.session.name, "TelescopeResultsNumber" },
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
  local json_str = vim.fn.system "gh mrva list --json | jq '. |= sort_by(.timestamp)'"
  local sessions = vim.fn.json_decode(json_str)
  pickers
    .new({}, {
      prompt_title = "MRVA session",
      finder = finders.new_table {
        results = sessions,
        entry_maker = gen_from_gh_mrva_list(),
      },
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          M.load(selection.value)
        end)
        return true
      end,
    })
    :find()
end

return M
