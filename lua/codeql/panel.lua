local util = require "codeql.util"
local config = require "codeql.config"
local Popup = require "nui.popup"
local autocmd = require "nui.utils.autocmd"
local event = autocmd.event
local vim = vim

local range_ns = vim.api.nvim_create_namespace "codeql"
local panel_short_help = true
local icon_closed = "▶"
local icon_open = "▼"

-- Render process:
--   render()
--     render_content()
--       print_help()
--       print_header()
--       print_issues()
--         print_tree_nodes()
--           print_tree_node()

-- global variables
local M = {
  panels = {},
  ns = range_ns
}

_G.generate_issue_label = function(node)
  local label = node.label
  local conf = config.values
  if conf.panel.show_filename and node["filename"] and node["filename"] ~= nil then
    if conf.panel.long_filename then
      label = node.filename
    elseif #vim.fn.fnamemodify(node.filename, ":p:t") > 0 then
      label = vim.fn.fnamemodify(node.filename, ":p:t")
    else
      label = node.label
    end
    if node.line and node.line > 0 then
      label = label .. ":" .. node.line
    end
  end
  return label
end

local function register(bufnr, obj)
  local curline = vim.api.nvim_buf_line_count(bufnr)
  M.panels[bufnr].line_map[curline] = obj
end

local function flatten_label(text)
  return table.concat(vim.split(text, "\n"), " \\n ")
end

local function print_to_panel(bufnr, text, matches)
  text = flatten_label(text)

  vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, { text })
  if type(matches) == "table" then
    for hlgroup, groups in pairs(matches) do
      for _, group in ipairs(groups) do
        local linenr = vim.api.nvim_buf_line_count(bufnr) - 1
        vim.api.nvim_buf_add_highlight(bufnr, 0, hlgroup, linenr, group[1], group[2])
      end
    end
  end
end

local function get_panel_window(bufnr)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == bufnr then
      return w
    end
  end
  return nil
end

local function go_to_main_window(panel_name)
  -- go to the wider window
  local widerwin = 0
  local widerwidth = 0
  local current_tab = vim.api.nvim_get_current_tabpage()
  local tab_windows = vim.api.nvim_tabpage_list_wins(current_tab)

  for _, w in ipairs(tab_windows) do
    if vim.api.nvim_win_get_width(w) > widerwidth then
      if vim.api.nvim_win_get_buf(w) ~= vim.fn.bufnr(panel_name) then
        widerwin = w
        widerwidth = vim.api.nvim_win_get_width(w)
      end
    end
  end
  if widerwin > -1 then
    vim.fn.win_gotoid(widerwin)
  end
end

local function is_filtered(filter, issue)
  local f, err = loadstring("return function(issue) return " .. filter .. " end")
  if f then
    return f()(issue)
  else
    return f, err
  end
end

local function print_help(bufnr)
  util.debug("Entering panel.print_help()")
  if panel_short_help then
    print_to_panel(bufnr, '" Press H for help')
    print_to_panel(bufnr, "")
  else
    print_to_panel(bufnr, '" --------- General ---------')
    print_to_panel(bufnr, '" <CR>: Jump to tag definition')
    print_to_panel(bufnr, '" p: As above, but dont change window')
    print_to_panel(bufnr, '" P: Previous path')
    print_to_panel(bufnr, '" N: Next path')
    print_to_panel(bufnr, '"')
    print_to_panel(bufnr, '" --------- Filters ---------')
    print_to_panel(bufnr, '" f: Label filter')
    print_to_panel(bufnr, '" F: Generic filter')
    print_to_panel(bufnr, '" x: Clear filter')
    print_to_panel(bufnr, '" s: Shortest path filter')
    print_to_panel(bufnr, '"')
    print_to_panel(bufnr, '" ---------- Folds ----------')
    print_to_panel(bufnr, '" o: Toggle fold')
    print_to_panel(bufnr, '" O: Open all folds')
    print_to_panel(bufnr, '" C: Close all folds')
    print_to_panel(bufnr, '"')
    print_to_panel(bufnr, '" ---------- Misc -----------')
    print_to_panel(bufnr, '" m: Toggle mode')
    print_to_panel(bufnr, '" q: Close window')
    print_to_panel(bufnr, '" H: Toggle help')
    print_to_panel(bufnr, "")
  end
end

local function get_node_location(node)
  if node.line and node.filename then
    local line = ""
    if node.line > -1 then
      line = string.format(":%d", node.line)
    end
    local filename
    local conf = config.values
    if conf.panel.long_filename then
      filename = node.filename
    else
      filename = vim.fn.fnamemodify(node.filename, ":p:t")
    end
    return filename .. line
  else
    return ""
  end
end

local function print_tree_node(bufnr, node, indent_level)
  local start_time = util.debug("Entering panel.print_tree_node()")
  local text = ""
  local hl = {}

  -- mark
  local mark = string.rep(" ", indent_level) .. node.mark .. " "
  local mark_hl_name = ""
  if node.mark == "≔" then
    mark_hl_name = "CodeqlPanelLabel"
  else
    mark_hl_name = node.visitable and "CodeqlPanelVisitable" or "CodeqlPanelNonVisitable"
  end
  hl[mark_hl_name] = { { 0, string.len(mark) } }

  -- text
  if node.filename then
    local location = get_node_location(node)
    text = string.format("%s%s - %s", mark, location, node.label)

    local sep_index = string.find(text, " - ", 1, true)

    hl["CodeqlPanelFile"] = { { string.len(mark), sep_index } }
    hl["CodeqlPanelSeparator"] = { { sep_index, sep_index + 2 } }
  else
    text = mark .. "[" .. node.label .. "]"
  end
  print_to_panel(bufnr, text, hl)

  register(bufnr, {
    kind = "node",
    obj = node,
  })
  util.debug("Exiting panel.print_tree_node()", { start_time = start_time })
end

local function left_align(text, size)
  return text .. string.rep(" ", size - vim.fn.strdisplaywidth(text))
end

local function right_align(text, size)
  return string.rep(" ", size - vim.fn.strdisplaywidth(text)) .. text
end

local function center_align(text, size)
  local pad = size - vim.fn.strdisplaywidth(text)
  local left_pad = math.floor(pad / 2)
  local right_pad = pad - left_pad
  return string.rep(" ", left_pad) .. text .. string.rep(" ", right_pad)
end

local function align(text, size)
  local alignment = config.values.panel.alignment
  if alignment == "left" then
    return left_align(text, size)
  elseif alignment == "right" then
    return right_align(text, size)
  elseif alignment == "center" then
    return center_align(text, size)
  else
    return text
  end
end

-- returns a tuple, where the first element is a list of the column labels and the second
-- element is a list of column locations
local function get_row_columns(issue, max_lengths)
  local path = issue.paths[1]
  local labels = {}
  local locations = {}
  for i, node in ipairs(path) do
    table.insert(labels, align(flatten_label(node.label), max_lengths[i]))
    table.insert(locations, align(get_node_location(node), max_lengths[i]))
  end
  return { labels, locations }
end

local function print_tree_nodes(bufnr, issue, indent_level)
  local start_time = util.debug("Entering panel.print_tree_nodes()")
  local line_map = M.panels[bufnr].line_map
  local curline = vim.api.nvim_buf_line_count(bufnr)

  local paths = issue.paths

  -- paths
  local active_path = 1
  if #paths > 1 then
    if line_map[curline] and line_map[curline].kind == "issue" then
      -- retrieve path info from the line_map
      active_path = line_map[curline].obj.active_path
    end
    local str = active_path .. "/" .. #paths
    if line_map[curline + 1] then
      table.remove(line_map, curline + 1)
    end
    local text = string.rep(" ", indent_level) .. "Path: "
    local hl = { CodeqlPanelInfo = { { 0, string.len(text) } } }
    print_to_panel(bufnr, text .. str, hl)
    register(bufnr)
  end
  local path = paths[active_path]

  --  print path nodes
  for _, node in ipairs(path) do
    print_tree_node(bufnr, node, indent_level)
  end
  util.debug("Existing panel.print_tree_nodes()", { start_time = start_time })
end

local function print_header(bufnr, issues)
  util.debug("Entering panel.print_header()")
  if config.database.path then
    local hl = { CodeqlPanelInfo = { { 0, string.len "Database:" } } }
    print_to_panel(bufnr, "Database: " .. config.database.path, hl)
  elseif config.sarif.path then
    local hl = { CodeqlPanelInfo = { { 0, string.len "SARIF:" } } }
    local parts = vim.split(config.sarif.path, "/")
    local filename = parts[#parts]
    print_to_panel(bufnr, "SARIF: " .. filename, hl)
  end
  local hl = { CodeqlPanelInfo = { { 0, string.len "Issues:" } } }
  -- print_to_panel(bufnr, "Issues:   " .. table.getn(issues), hl)
  print_to_panel(bufnr, "Issues:   " .. #issues, hl)
end

local function get_column_names(columns, max_lengths)
  local result = {}
  for i, column in ipairs(columns) do
    table.insert(result, align(column, max_lengths[i]))
  end
  return result
end

local function min_path_length(paths)
  local min_length = #paths[1]
  for _, path in ipairs(paths) do
    if #path < min_length then
      min_length = #path
    end
  end
  return min_length
end

local function print_tree(bufnr, results)
  util.debug("Entering print_tree()")

  -- print group name
  local query_foldmarker = not results.is_folded and icon_open or icon_closed
  local query_label = string.format("%s %s", query_foldmarker, results.label)

  print_to_panel(bufnr, string.format("%s (%d)", query_label, #results.issues), {
    CodeqlPanelFoldIcon = { { 0, string.len(query_foldmarker) } },
    CodeqlPanelQueryId = { { string.len(query_foldmarker), string.len(query_label) } },
  })
  register(bufnr, {
    kind = "query",
    obj = results,
  })

  if not results.is_folded then
    -- print issue labels
    util.debug("Printing issue labels")
    for _, issue in ipairs(results.issues) do
      -- print nodes
      if not issue.hidden then
        local start_rtime = util.debug("Printing issue label")
        local is_folded = issue.is_folded
        local foldmarker = not is_folded and icon_open or icon_closed
        local label = string.format("  %s %s ↔ %d", foldmarker, issue.label, issue.min_path_length)
        print_to_panel(bufnr, label, {
          CodeqlPanelFoldIcon = { { 0, 2 + string.len(foldmarker) } },
          Normal = { { 2 + string.len(foldmarker), 2 + string.len(foldmarker) + string.len(issue.label) } },
          CodeqlPanelQueryId = { { 4 + string.len(foldmarker) + string.len(issue.label), 4 + string.len(foldmarker) + string.len(issue.label) + 2 } },
        })

        register(bufnr, {
          kind = "issue",
          obj = issue,
        })

        util.debug("Finished printing issue label", { start_time = start_rtime })
        if not is_folded then
          print_tree_nodes(bufnr, issue, 4)
        end
      end
    end
  end
  print_to_panel(bufnr, "")
end

local function print_table(bufnr, results)
  -- TODO: node.label may need to be tweaked (eg: replace new lines with "")
  -- and this is the place to do it

  util.debug("Entering print_table()")

  print_to_panel(bufnr, string.format("%s (%d)", results.label, #results.issues), {
    CodeqlPanelQueryId = { { 0, string.len(results.label) } },
  })

  -- calculate max length for each cell
  local max_lengths = {}
  for _, issue in ipairs(results.issues) do
    -- in table view, we only show the first path
    local path = issue.paths[1]
    -- in table view, each path node is a column
    for i, column in ipairs(path) do
      -- we need to take into account the length of the label and the location
      -- the cell length is the max of the label and the location
      max_lengths[i] = math.max(vim.fn.strdisplaywidth(flatten_label(column.label)), max_lengths[i] or -1)
      max_lengths[i] = math.max(vim.fn.strdisplaywidth(get_node_location(column)), max_lengths[i] or -1)
    end
  end
  if results.columns and #results.columns > 0 then
    for i, column in ipairs(results.columns) do
      max_lengths[i] = math.max(vim.fn.strdisplaywidth(column), max_lengths[i] or -1)
    end
  end

  --local total_length = 4
  --for _, len in ipairs(max_lengths) do
  --  total_length = total_length + len + 3
  --end
  print_to_panel(bufnr, "")

  local rows = {}
  for _, issue in ipairs(results.issues) do
    local row_columns = get_row_columns(issue, max_lengths)
    table.insert(rows, row_columns)
  end

  local bars = {}
  for _, len in ipairs(max_lengths) do
    table.insert(bars, string.rep("─", len))
  end

  local column_names = get_column_names(results.columns, max_lengths)

  -- header
  local header1 = string.format("┌─%s─┐", table.concat(bars, "─┬─"))
  print_to_panel(bufnr, header1, { CodeqlPanelSeparator = { { 0, -1 } } })
  if results.columns and #results.columns > 0 then
    local header2 = string.format("│ %s │", table.concat(column_names, " │ "))
    print_to_panel(bufnr, header2, { CodeqlPanelSeparator = { { 0, -1 } } })
    local header3 = string.format("├─%s─┤", table.concat(bars, "─┼─"))
    print_to_panel(bufnr, header3, { CodeqlPanelSeparator = { { 0, -1 } } })
  end

  local separator_hls = { { 0, vim.fn.len "│ " } }
  local acc = vim.fn.len "│ "
  for _, len in ipairs(max_lengths) do
    table.insert(separator_hls, { acc + len, acc + len + vim.fn.len " │ " })
    acc = acc + len + vim.fn.len " │ "
  end

  local location_hls = {}
  acc = vim.fn.len "│ "
  for _, len in ipairs(max_lengths) do
    table.insert(location_hls, { acc, acc + len })
    acc = acc + len + vim.fn.len " │ "
  end

  local hl_labels = { CodeqlPanelSeparator = separator_hls }
  local hl_locations = { CodeqlPanelSeparator = separator_hls, Comment = location_hls }
  for i, row in ipairs(rows) do
    -- labels
    local r = string.format("│ %s │", table.concat(row[1], " │ "))
    print_to_panel(bufnr, r, hl_labels)
    register(bufnr, {
      kind = "row",
      obj = {
        ranges = location_hls,
        columns = results.issues[i].paths[1],
      },
    })

    -- locations
    r = string.format("│ %s │", table.concat(row[2], " │ "))
    print_to_panel(bufnr, r, hl_locations)
    register(bufnr, {
      kind = "row",
      obj = {
        ranges = location_hls,
        columns = results.issues[i].paths[1],
      },
    })

    if i < #rows then
      -- row separator
      r = string.format("├─%s─┤", table.concat(bars, "─┼─"))
    else
      -- footer
      r = string.format("└─%s─┘", table.concat(bars, "─┴─"))
    end
    print_to_panel(bufnr, r, { CodeqlPanelSeparator = { { 0, -1 } } })
  end
  print_to_panel(bufnr, "")
end

local function print_issues(bufnr, results)
  local start_time = util.debug("Entering panel.print_issues()")
  if results.mode == "tree" then
    start_time = util.debug("Entering panel.print_issues():tree mode")
    print_tree(bufnr, results)
  elseif results.mode == "table" then
    start_time = util.debug("Entering panel.print_issues():table mode")
    print_table(bufnr, results)
  end
  util.debug("Exiting panel.print_issues()", { start_time = start_time })
end

local function render_content(bufnr)
  local start_time = util.debug("Entering panel.render_content()")
  if not bufnr or bufnr == -1 then
    util.err_message "Error opening CodeQL panel"
    return
  end
  local panel = M.panels[bufnr]

  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  print_help(bufnr)

  if #panel.issues > 0 then
    print_header(bufnr, panel.issues)
    print_to_panel(bufnr, "")
    for _, query in ipairs(panel.queries) do
      print_issues(bufnr, query)
    end

    local win = get_panel_window(bufnr)
    local lcount = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(win, { math.min(7, lcount), 0 })
  else
    print_to_panel(bufnr, "No results found.")
  end
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  util.debug("Existing panel.render_content()", { start_time = start_time })
end

local function render_keep_view(bufnr, line)
  local start_time = util.debug("Entering panel.render_keep_view()")
  if line == nil then
    line = vim.fn.line "."
  end

  -- called from toggle_fold commands, so within panel buffer
  local curcol = vim.fn.col "."
  local topline = vim.fn.line "w0"

  render_content(bufnr)

  local scrolloff_save = vim.api.nvim_get_option "scrolloff"
  vim.cmd "set scrolloff=0"

  vim.fn.cursor(topline, 1)
  vim.cmd "normal! zt"
  vim.fn.cursor(line, curcol)

  local start_rtime = util.debug("Redrawing the screen")
  vim.cmd("let &scrolloff = " .. scrolloff_save)
  vim.cmd "redraw"
  util.debug("Finishing redrawing the screen", { start_time = start_rtime })
  util.debug("Exiting panel.render_keep_view()", { start_time = start_time })
end

-- exported functions

function M.apply_mappings()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "o",
    [[<cmd>lua require'codeql.panel'.toggle_fold()<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "m",
    [[<cmd>lua require'codeql.panel'.toggle_mode()<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<CR>",
    [[<cmd>lua require'codeql.panel'.jump_to_code(false)<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "p",
    [[<cmd>lua require'codeql.panel'.jump_to_code(true)<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "s",
    [[<cmd>lua require'codeql.panel'.preview_snippet(true)<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<S-h>",
    [[<cmd>lua require'codeql.panel'.toggle_help()<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "q",
    [[<cmd>lua require'codeql.panel'.close_panel()<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<S-o>",
    [[<cmd>lua require'codeql.panel'.set_fold_level(false)<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<S-c>",
    [[<cmd>lua require'codeql.panel'.set_fold_level(true)<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<S-p>",
    [[<cmd>lua require'codeql.panel'.change_path(-1)<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "N",
    [[<cmd>lua require'codeql.panel'.change_path(1)<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "f",
    [[<cmd>lua require'codeql.panel'.label_filter()<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<S-f>",
    [[<cmd>lua require'codeql.panel'.generic_filter()<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "x",
    [[<cmd>lua require'codeql.panel'.clear_filter()<CR>]],
    { script = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "s",
    [[<cmd>lua require'codeql.panel'.filter_shortest_path()<CR>]],
    { script = true, silent = true }
  )
end

local function unhide_issues(issues)
  for _, issue in ipairs(issues) do
    issue.hidden = false
  end
end

local function filter_issues(issues, filter_str)
  for _, issue in ipairs(issues) do
    if not is_filtered(filter_str, issue) then
      issue.hidden = true
    end
  end
end

function M.filter_shortest_path()
  local bufnr = vim.api.nvim_get_current_buf()
  local panel = M.panels[bufnr]
  local queries = panel.queries
  for _, query in ipairs(queries) do
    -- filter issues reaching the same sink, keeping only the shortest path
    local issues = query.issues
    local sinks = {}
    for _, issue in ipairs(issues) do
      issue.hidden = true
      local key = issue.node.url.uri ..
          ":" ..
          issue.node.url.startLine ..
          ":" .. issue.node.url.startColumn .. ":" .. issue.node.url.endLine .. ":" .. issue.node.url.endColumn

      if sinks[key] then
        if sinks[key].min_path_length > issue.min_path_length then
          sinks[key] = issue
        end
      else
        sinks[key] = issue
      end
    end
    for _, issue in pairs(sinks) do
      issue.hidden = false
    end
  end
  render_content(bufnr)
end

function M.clear_filter()
  local bufnr = vim.api.nvim_get_current_buf()
  local panel = M.panels[bufnr]
  unhide_issues(panel.issues)
  render_content(bufnr)
end

function M.label_filter()
  local bufnr = vim.api.nvim_get_current_buf()
  local panel = M.panels[bufnr]
  local pattern = vim.fn.input "Pattern: "
  unhide_issues(panel.issues)
  filter_issues(
    panel.issues,
    string.format("string.match(string.lower(generate_issue_label(issue.node)), string.lower('%s')) ~= nil", pattern)
  )
  render_content(bufnr)
end

function M.generic_filter()
  local bufnr = vim.api.nvim_get_current_buf()
  local panel = M.panels[bufnr]
  local pattern = vim.fn.input "Pattern: "
  unhide_issues(panel.issues)
  filter_issues(panel.issues, pattern)
  render_content(bufnr)
end

function M.toggle_mode()
  local bufnr = vim.api.nvim_get_current_buf()
  local panel = M.panels[bufnr]
  if panel.mode == "tree" then
    panel.mode = "table"
  elseif panel.mode == "table" then
    panel.mode = "tree"
  end
  M.render({
    issues = panel.issues,
    source = panel.source,
    mode = panel.mode,
    columns = panel.columns,
    panel_name = vim.fn.bufname(bufnr),
  })
end

local function get_enclosing_issue(line)
  local bufnr = vim.api.nvim_get_current_buf()
  local line_map = M.panels[bufnr].line_map
  local entry
  while line >= 7 do
    entry = line_map[line]
    if entry
        and (entry.kind == "node" or entry.kind == "issue" or entry.kind == "query")
        and vim.tbl_contains(vim.tbl_keys(entry.obj), "is_folded")
    then
      return line, entry.obj
    end
    line = line - 1
  end
end

function M.toggle_fold()
  local start_time = util.debug("Entering panel.toggle_fold()")
  local bufnr = vim.api.nvim_get_current_buf()
  -- prevent highlighting from being off after adding/removing the help text
  vim.cmd "match none"

  local line = vim.fn.line "."
  local enc_line, issue = get_enclosing_issue(line)
  if issue and vim.tbl_contains(vim.tbl_keys(issue), "is_folded") then
    issue.is_folded = not issue.is_folded
    render_keep_view(bufnr, line)
    vim.api.nvim_win_set_cursor(0, { enc_line, 0 })
  end
  util.debug("Exiting panel.toggle_fold()", { start_time = start_time })
end

function M.toggle_help()
  local start_time = util.debug("Entering panel.toggle_help()")
  local bufnr = vim.api.nvim_get_current_buf()
  panel_short_help = not panel_short_help
  -- prevent highlighting from being off after adding/removing the help text
  render_keep_view(bufnr)
  util.debug("Exiting panel.toggle_help()", { start_time = start_time })
end

function M.set_fold_level(level)
  local bufnr = vim.api.nvim_get_current_buf()
  local line_map = M.panels[bufnr].line_map
  for k, _ in pairs(line_map) do
    line_map[k].obj.is_folded = level
  end
  render_keep_view(bufnr)
end

function M.change_path(offset)
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.fn.line "."
  local enc_line, issue = get_enclosing_issue(line)

  if issue.active_path then
    if issue.active_path == 1 and offset == -1 then
      issue.active_path = #issue.paths
    elseif issue.active_path == #issue.paths and offset == 1 then
      issue.active_path = 1
    else
      issue.active_path = issue.active_path + offset
    end
    render_keep_view(bufnr, line + 1)
    vim.api.nvim_win_set_cursor(0, { enc_line, 0 })
  end
end

local function get_column_at_cursor(row)
  local ranges = row.ranges
  local cur = vim.api.nvim_win_get_cursor(0)
  for i, range in ipairs(ranges) do
    if tonumber(range[1]) <= tonumber(cur[2]) and tonumber(cur[2]) <= tonumber(range[2]) then
      return row.columns[i]
    end
  end
end

local function get_current_node()
  local bufnr = vim.api.nvim_get_current_buf()
  local line_map = M.panels[bufnr].line_map
  if not line_map[vim.fn.line "."] then
    return
  end

  local node
  local entry = line_map[vim.fn.line "."]
  if entry.kind == "issue" then
    node = entry.obj.node
  elseif entry.kind == "node" then
    node = entry.obj
  elseif entry.kind == "row" then
    node = get_column_at_cursor(entry.obj)
  end
  return node
end

function M.jump_to_code(stay_in_panel)
  local node = get_current_node()
  if not node or not node.visitable then
    return
  end

  local filename = node.filename
  if string.sub(filename, 1, 1) == "/" then
    filename = string.sub(filename, 2)
  end

  local source
  if config.database.sourceArchiveZip and util.is_file(config.database.sourceArchiveZip) then
    source = "source_archive"
  elseif config.sarif.path and util.is_file(config.sarif.path) and config.sarif.hasArtifacts then
    source = "sarif"
  elseif util.is_file(vim.fn.getcwd() .. util.uri_to_fname("/" .. filename)) then
    source = "file_system"
  elseif node.versionControlProvenance then
    source = "vcs"
  end

  if not source then
    util.err_message("Cannot figure out source code origin. Try setting up the database")
    return
  end

  -- save audit pane window
  local panel_winid = vim.fn.win_getid()

  -- choose the target window to open the file in
  local target_winid = require("window-picker").pick_window()

  -- go to the target window
  vim.fn.win_gotoid(target_winid)

  local bufname, revisionId, nwo
  if source == "source_archive" or source == "sarif" then
    -- create the ql:// buffer
    bufname = string.format("ql://%s", filename)
  elseif source == "file_system" then
    bufname = vim.fn.getcwd() .. "/" .. filename
  elseif source == "vcs" then
    local repositoryUri = node.versionControlProvenance.repositoryUri
    revisionId = node.versionControlProvenance.revisionId
    nwo = vim.split(repositoryUri, "github.com/")[2]
    bufname = string.format("ql://%s/%s/%s", nwo, revisionId, filename)
  end

  local opts = {
    nwo = nwo,
    revisionId = revisionId,
    line = node.line,
    startLine = node.url.startLine,
    endLine = node.url.endLine,
    startColumn = node.url.startColumn,
    endColumn = node.url.endColumn,
    stay_in_panel = stay_in_panel,
    panel_winid = panel_winid,
    target_winid = target_winid,
    range_ns = range_ns,
  }

  local bufnr = vim.fn.bufnr(bufname)
  if bufnr > -1 then
    -- buffer already exists, show it
    vim.api.nvim_command(string.format("buffer %s", bufname))
    if opts.line then
      util.jump_to_line(opts)
    end
    if opts.startLine and opts.endLine and opts.startColumn and opts.endColumn then
      util.highlight_range(bufnr, opts)
    end
  else
    if source == "sarif" then
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, bufname)
      util.open_from_sarif(bufnr, filename, opts)
    elseif source == "source_archive" then
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, bufname)
      util.open_from_archive(bufnr, filename, opts)
    elseif source == "vcs" then
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, bufname)
      util.open_from_vcs(bufnr, filename, opts)
    end
  end
  if bufnr > -1 then
    vim.api.nvim_win_set_buf(target_winid, bufnr)
  else
    util.err_message("Cannot find source code for " .. filename .. " in " .. source)
  end
end

function M.preview_snippet()
  local node = get_current_node()
  if not node or not node.visitable then
    return
  end
  local conf = config.values
  local context_lines = conf.panel.context_lines
  local snippet = {}
  local max_len = 0
  local context_start_line
  if config.sarif.path and node.contextRegion and node.contextRegion.snippet then
    snippet = vim.split(node.contextRegion.snippet.text, "\n")
    context_start_line = node.contextRegion.startLine
    for _, line in ipairs(snippet) do
      if #line > max_len then
        max_len = #line
      end
    end
  elseif config.sarif.path and config.sarif.hasArtifacts then
    local sarif = util.read_json_file(config.sarif.path)
    local artifacts = sarif.runs[1].artifacts
    for _, artifact in ipairs(artifacts) do
      local uri = "/" .. util.uri_to_fname(artifact.location.uri)
      if uri == node.filename then
        local content = vim.split(artifact.contents.text, "\n")
        context_start_line = math.max(node.url.startLine - context_lines, 0)
        local context_end_line = math.min(node.url.startLine + context_lines, #content)
        for i = context_start_line, context_end_line do
          table.insert(snippet, content[i])
          if #content[i] > max_len then
            max_len = #content[i]
          end
        end
        break
      end
    end
  elseif config.database.sourceArchiveZip then
    local zipfile = config.database.sourceArchiveZip
    local path = string.gsub(node.filename, "^/", "")
    local content = vim.fn.systemlist(string.format("unzip -p -- %s %s", zipfile, path))
    context_start_line = math.max(node.url.startLine - context_lines, 0)
    local context_end_line = math.min(node.url.startLine + context_lines, #content)
    for i = context_start_line, context_end_line do
      table.insert(snippet, content[i])
      if #content[i] > max_len then
        max_len = #content[i]
      end
    end
  end

  -- create popup window
  local popup = Popup {
    enter = false,
    focusable = false,
    relative = "editor",
    border = {
      style = "rounded",
    },
    position = "50%",
    size = {
      width = max_len + 10,
      height = #snippet + 2,
    },
    buf_options = {
      modifiable = true,
      readonly = false,
      filetype = "markdown",
    },
    win_options = {
      winblend = 10,
      winhighlight = "Normal:NormalAlt,FloatBorder:FloatBorder",
    },
  }

  -- when cursor is moved, close the popup
  local current_bufnr = vim.api.nvim_get_current_buf()
  autocmd.buf.define(current_bufnr, event.CursorMoved, function()
    popup:unmount()
  end, { once = true })

  -- mount/open the component
  popup:mount()

  -- set content
  local _, _, ext = string.find(node.filename, "%.(%w+)$")
  local content = { "```" .. ext }
  vim.list_extend(content, snippet)
  vim.list_extend(content, { "```" })
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, content)

  -- highlight node
  vim.api.nvim_buf_clear_namespace(popup.bufnr, range_ns, 0, -1)
  local startLine = node.url.startLine - context_start_line
  local startColumn = node.url.startColumn
  local endColumn = node.url.endColumn
  vim.api.nvim_buf_add_highlight(popup.bufnr, range_ns, "CodeqlRange", startLine + 1, startColumn - 1, endColumn - 1)
end

function M.open_panel(panel_name)
  local bufnr = vim.fn.bufnr(panel_name)
  local conf = config.values

  -- check if audit pane is already opened
  if get_panel_window(bufnr) then
    return bufnr, get_panel_window(bufnr)
  end

  -- get current win id
  local current_window = vim.fn.win_getid()

  -- go to main window
  go_to_main_window(panel_name)

  -- split
  vim.fn.execute("silent keepalt " .. conf.panel.pos .. " vertical " .. conf.panel.width .. "split " .. panel_name)
  bufnr = vim.fn.bufnr(panel_name)

  -- go to original window
  vim.fn.win_gotoid(current_window)

  -- buffer options
  vim.api.nvim_buf_set_option(bufnr, "filetype", "codeql_panel")
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
  vim.api.nvim_buf_set_option(bufnr, "buflisted", false)

  -- window options
  local winnr = get_panel_window(bufnr)
  vim.api.nvim_win_set_option(winnr, "wrap", false)
  vim.api.nvim_win_set_option(winnr, "number", false)
  vim.api.nvim_win_set_option(winnr, "relativenumber", false)
  vim.api.nvim_win_set_option(winnr, "foldenable", false)
  vim.api.nvim_win_set_option(winnr, "winfixwidth", true)
  vim.api.nvim_win_set_option(winnr, "concealcursor", "nvi")
  vim.api.nvim_win_set_option(winnr, "conceallevel", 3)
  vim.api.nvim_win_set_option(winnr, "signcolumn", "yes")
  return bufnr, winnr
end

function M.close_panel()
  vim.api.nvim_win_close(0, true)
end

function M.render(opts)
  util.debug("Entering panel.render()")
  opts = opts or {}
  local issues = opts.issues or {}
  local panel_name = opts.panel_name or "__CodeQLPanel__"
  local bufnr = M.open_panel(panel_name)

  M.panels[bufnr] = {
    issues = issues or {},
    source = opts.source or "raw",
    columns = opts.columns or {},
    mode = opts.mode or "table",
    line_map = {},
  }

  -- split issues in groups according to the query that generated them
  local query_groups = {}
  for _, issue in ipairs(issues) do
    -- pre-compute expensive values
    issue.label = generate_issue_label(issue.node)
    issue.min_path_length = min_path_length(issue.paths)

    if query_groups[issue.query_id] then
      table.insert(query_groups[issue.query_id], issue)
    else
      query_groups[issue.query_id] = { issue }
    end
  end


  local queries = {}
  local folded = #vim.tbl_keys(query_groups) > 1 and true or false
  for query_id, query_issues in pairs(query_groups) do
    local query = {
      mode = opts.mode or "table",
      columns = opts.columns and opts[query_id] or {},
      issues = query_issues,
      is_folded = folded,
      label = query_id,
    }
    table.insert(queries, query)
  end
  M.panels[bufnr].queries = queries

  render_content(bufnr)
end

return M
