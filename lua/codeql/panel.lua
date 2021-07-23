local util = require'codeql.util'
local vim = vim
local api = vim.api
local format = string.format

local range_ns = api.nvim_create_namespace("codeql")
local panel_buffer_name = '__CodeQLPanel__'
local panel_pos = 'right'
local panel_width = 50
local panel_short_help = true
local icon_closed = '▶'
local icon_open = '▼'

-- global variables
local issues = {}
local columns = {}
local kind
local mode
local line_map = {}


-- local functions

local function register(obj)
  local bufnr = vim.fn.bufnr(panel_buffer_name)
  local curline = api.nvim_buf_line_count(bufnr)
  line_map[curline] = obj
end

local function print_to_panel(text, matches)
  local bufnr = vim.fn.bufnr(panel_buffer_name)
  api.nvim_buf_set_lines(bufnr, -1, -1, true, {text})
  if type(matches) == 'table' then
    for hlgroup, groups in pairs(matches) do
      for _, group in ipairs(groups) do
        local linenr = api.nvim_buf_line_count(bufnr) - 1
        api.nvim_buf_add_highlight(bufnr, 0, hlgroup, linenr, group[1], group[2])
      end
    end
  end
end

local function get_panel_window(buffer_name)
  local bufnr = vim.fn.bufnr(buffer_name)
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(w) == bufnr then
      return w
    end
  end
  return nil
end

local function go_to_main_window()
  -- go to the wider window
  local widerwin = 0
  local widerwidth = 0
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_width(w) > widerwidth then
      if vim.api.nvim_win_get_buf(w) ~= vim.fn.bufnr(panel_buffer_name) then
        widerwin = w
        widerwidth = api.nvim_win_get_width(w)
      end
    end
  end
  if widerwin > -1 then
    vim.fn.win_gotoid(widerwin)
  end
end

local function is_filtered(filter, issue)
  local f, err = loadstring("return function(issue) return " .. filter .. " end")
  if f then return f()(issue) else return f, err end
end

local function filter_issues(filter_str)
  for _, issue in ipairs(issues) do
    if not is_filtered(filter_str, issue) then
      issue.hidden = true
    end
  end
end

local function unhide_issues()
  for _, issue in ipairs(issues) do
    issue.hidden = false
  end
end

local function print_help()
  if panel_short_help then
    print_to_panel('" Press H for help')
    print_to_panel('')
  else
    print_to_panel('" --------- General ---------')
    print_to_panel('" <CR>: Jump to tag definition')
    print_to_panel('" p: As above, but dont change window')
    print_to_panel('" P: Previous path')
    print_to_panel('" N: Next path')
    print_to_panel('"')
    print_to_panel('" ---------- Folds ----------')
    print_to_panel('" f: Label filter')
    print_to_panel('" F: Generic filter')
    print_to_panel('" x: Clear filter')
    print_to_panel('"')
    print_to_panel('" ---------- Folds ----------')
    print_to_panel('" o: Toggle fold')
    print_to_panel('" O: Open all folds')
    print_to_panel('" C: Close all folds')
    print_to_panel('"')
    print_to_panel('" ---------- Misc -----------')
    print_to_panel('" m: Toggle mode')
    print_to_panel('" q: Close window')
    print_to_panel('" H: Toggle help')
    print_to_panel('')
  end
end

local function get_node_location(node)
  if node.line and node.filename then
    local line = ""
    if node.line > -1 then
      line = format(":%d", node.line)
    end

    local filename
    if vim.g.codeql_panel_longnames then
      filename = node.filename
    else
      filename = vim.fn.fnamemodify(node.filename, ':p:t')
    end
    return filename..line
  else
    return ""
  end
end

local function print_tree_node(node, indent_level)
  local text = ''
  local hl = {}

  -- mark
  local mark = string.rep(' ', indent_level)..node.mark..' '
  local mark_hl_name = ''
  if node.mark == '≔' then
    mark_hl_name = 'CodeqlPanelLabel'
  else
    mark_hl_name = node.visitable and 'CodeqlPanelVisitable' or 'CodeqlPanelNonVisitable'
  end
  hl[mark_hl_name] = {{0, string.len(mark)}}

  -- text
  if node.filename then

    local location = get_node_location(node)
    text = format("%s%s - %s", mark, location, node.label)

    local sep_index = string.find(text, ' - ', 1, true)

    hl['CodeqlPanelFile'] = {{ string.len(mark), sep_index }}
    hl['CodeqlPanelSeparator'] = {{ sep_index, sep_index + 2 }}
  else
    text = mark..'['..node.label..']'
  end
  print_to_panel(text, hl)

  -- register the node in the line_map
  register({
    kind = "node",
    obj = node
  })
end

local function right_align(text, size)
  return string.rep(" ", size - vim.fn.strdisplaywidth(text)) .. text
end

local function center_align(text, size)
  local pad = size - vim.fn.strdisplaywidth(text)
  local left_pad = math.floor(pad/2)
  local right_pad = pad - left_pad
  return string.rep(" ", left_pad) .. text .. string.rep(" ", right_pad)
end

local function get_table_nodes(issue, max_lengths)
  local path = issue.paths[1]
  local labels = {}
  local locations = {}
  for i, node in ipairs(path) do
    table.insert(labels, center_align(node.label, max_lengths[i]))
    table.insert(locations, center_align(get_node_location(node), max_lengths[i]))
  end
  return {labels, locations}
end

local function print_tree_nodes(issue, indent_level)

  local bufnr = vim.fn.bufnr(panel_buffer_name)
  local curline = api.nvim_buf_line_count(bufnr)

  local paths = issue.paths

  -- paths
  local active_path = 1
  if #paths > 1 then
    if line_map[curline] and line_map[curline].kind == "issue" then
      -- retrieve path info from the line_map
      active_path = line_map[curline].obj.active_path
    end
    local str = active_path..'/'..#paths
    if line_map[curline + 1] then
      table.remove(line_map, curline + 1)
    end
    local text = string.rep(' ', indent_level)..'Path: '
    local hl = { CodeqlPanelInfo = {{0, string.len(text)}} }
    print_to_panel(text..str, hl)
    register(nil)
  end
  local path = paths[active_path]

  --  print path nodes
  for _, node in ipairs(path) do
    print_tree_node(node, indent_level)
  end
end

local function print_header()
  local hl = { CodeqlPanelInfo = {{0, string.len('Database:')}} }
  local database = vim.g.codeql_database.path
  print_to_panel('Database: '..database, hl)
  hl = { CodeqlPanelInfo = {{0, string.len('Issues:')}} }
  print_to_panel('Issues:   '..table.getn(issues), hl)
  --print_to_panel('')
end

local function get_column_names(max_lengths)
  local result = {}
  for i, column in ipairs(columns) do
    table.insert(result, center_align(column, max_lengths[i]))
  end
  return result
end

local function print_issues()
  local last_rule_id

  if mode == "tree" then
    -- print issue labels
    for _, issue in ipairs(issues) do

      -- print nodes
      if issue.hidden then goto continue end

      local is_folded = issue.is_folded
      local foldmarker = not is_folded and icon_open or icon_closed

      if last_rule_id ~= issue.rule_id then
        print_to_panel('')
        print_to_panel(
          issue.rule_id,
          { CodeqlPanelRuleId = {{ 0, string.len(issue.rule_id) }} }
        )
        last_rule_id = issue.rule_id
      end

      print_to_panel(
        format('%s %s', foldmarker, issue.label),
        { CodeqlPanelFoldIcon = {{ 0, string.len(foldmarker) }} }
      )

      -- register the issue in the line_map
      register({
        kind = "issue",
        obj = issue
      })

      if not is_folded then
        print_tree_nodes(issue, 2)
      end
      ::continue::
    end

  elseif mode == "table" then

    -- TODO: node.label may need to be tweaked (eg: replace new lines with "")
    -- and this is the place to do it

    -- calculate max length for each cell
    local max_lengths = {}
    for _, issue in ipairs(issues) do
      local path = issue.paths[1]
      for i, node in ipairs(path) do
        max_lengths[i] = math.max(vim.fn.strdisplaywidth(node.label), max_lengths[i] or -1)
        max_lengths[i] = math.max(vim.fn.strdisplaywidth(get_node_location(node)), max_lengths[i] or -1)
      end
    end
    if columns then
      for i, column in ipairs(columns) do
        max_lengths[i] = math.max(vim.fn.strdisplaywidth(column), max_lengths[i] or -1)
      end
    end


    local total_length = 4
    for _, len in ipairs(max_lengths) do
      total_length = total_length + len + 3
    end
    print_to_panel('')

    local rows = {}
    for _, issue in ipairs(issues) do
      table.insert(rows, get_table_nodes(issue, max_lengths))
    end

    local bars = {}
    for _, len in ipairs(max_lengths) do
      table.insert(bars, string.rep("─", len))
    end

    local column_names = get_column_names(max_lengths)

    local header1 = string.format("┌─%s─┐", table.concat(bars, "─┬─"))
    print_to_panel(header1, {CodeqlPanelSeparator = {{0,-1}}})
    local header2 = string.format("│ %s │", table.concat(column_names, " │ "))
    print_to_panel(header2, {CodeqlPanelSeparator = {{0,-1}}})
    local header3 = string.format("├─%s─┤", table.concat(bars, "─┼─"))
    print_to_panel(header3, {CodeqlPanelSeparator = {{0,-1}}})

    local separator_hls = { {0, vim.fn.len("│ ")} }
    local acc = vim.fn.len("│ ")
    for _, len in ipairs(max_lengths) do
      table.insert(separator_hls, { acc + len, acc + len + vim.fn.len(" │ ")})
      acc = acc + len + vim.fn.len(" │ ")
    end

    local location_hls = {}
    acc = vim.fn.len("│ ")
    for _, len in ipairs(max_lengths) do
      table.insert(location_hls, { acc,  acc + len})
      acc = acc + len + vim.fn.len(" │ ")
    end

    local hl_labels = {CodeqlPanelSeparator = separator_hls}
    local hl_locations = {CodeqlPanelSeparator = separator_hls; Comment = location_hls}
    for i, row in ipairs(rows) do

      -- labels
      local r = string.format("│ %s │", table.concat(row[1], " │ "))
      print_to_panel(r, hl_labels)
      -- register the issue in the line_map
      register({
        kind = "row",
        obj = {
          ranges = location_hls,
          columns = issues[i].paths[1]
        }
      })

      -- locations
      r = string.format("│ %s │", table.concat(row[2], " │ "))
      print_to_panel(r, hl_locations)
      -- register the issue in the line_map
      register({
        kind = "row",
        obj = {
          ranges = location_hls,
          columns = issues[i].paths[1]
        }
      })

      if i < #rows then
        r = string.format("├─%s─┤", table.concat(bars, "─┼─"))
        print_to_panel(r, {CodeqlPanelSeparator = {{0,-1}}})
      end
    end
    local footer = string.format("└─%s─┘", table.concat(bars, "─┴─"))
    print_to_panel(footer, {CodeqlPanelSeparator = {{0,-1}}})
  end
end

local function render_content()

  local bufnr = vim.fn.bufnr(panel_buffer_name)
  if bufnr == -1 then util.err_message('Error opening CodeQL panel'); return end

  api.nvim_buf_set_option(bufnr, 'modifiable', true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  print_help()

  if #issues > 0 then

    print_header()
    print_issues()

    local win = get_panel_window(panel_buffer_name)
    local lcount = api.nvim_buf_line_count(bufnr)
    api.nvim_win_set_cursor(win, {math.min(7,lcount), 0})
  else
    print_to_panel('No results found.')
  end
  api.nvim_buf_set_option(bufnr, 'modifiable', false)
  util.message(' ')
end

local function render_keep_view(line)
  if line == nil then line = vim.fn.line('.') end

  -- called from toggle_fold commands, so within panel buffer
  local curcol = vim.fn.col('.')
  local topline = vim.fn.line('w0')

  render_content()

  local scrolloff_save = api.nvim_get_option('scrolloff')
  vim.cmd('set scrolloff=0')

  vim.fn.cursor(topline, 1)
  vim.cmd('normal! zt')
  vim.fn.cursor(line, curcol)

  vim.cmd('let &scrolloff = '..scrolloff_save)
  vim.cmd('redraw') -- consumes FDs
end

-- exported functions

local M = {}

function M.apply_mappings()
  local bufnr = api.nvim_get_current_buf()
  api.nvim_buf_set_keymap(bufnr, 'n', 'o', [[<cmd>lua require'codeql.panel'.toggle_fold()<CR>]], { script = true,  silent = true})
  api.nvim_buf_set_keymap(bufnr, 'n', 'm', [[<cmd>lua require'codeql.panel'.toggle_mode()<CR>]], { script = true,  silent = true})
  api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', [[<cmd>lua require'codeql.panel'.jump_to_code(false)<CR>]], { script = true,  silent = true})
  api.nvim_buf_set_keymap(bufnr, 'n', 'p', [[<cmd>lua require'codeql.panel'.jump_to_code(true)<CR>]], { script = true,  silent = true})
  api.nvim_buf_set_keymap(bufnr, 'n', '<S-h>', [[<cmd>lua require'codeql.panel'.toggle_help()<CR>]], { script = true,  silent = true})
  api.nvim_buf_set_keymap(bufnr, 'n', 'q', [[<cmd>lua require'codeql.panel'.close_panel()<CR>]], { script = true,  silent = true})
  api.nvim_buf_set_keymap(bufnr, 'n', '<S-o>', [[<cmd>lua require'codeql.panel'.set_fold_level(false)<CR>]], { script = true,  silent = true})
  api.nvim_buf_set_keymap(bufnr, 'n', '<S-c>', [[<cmd>lua require'codeql.panel'.set_fold_level(true)<CR>]], { script = true,  silent = true})
  api.nvim_buf_set_keymap(bufnr, 'n', '<S-p>', [[<cmd>lua require'codeql.panel'.change_path(-1)<CR>]], { script = true,  silent = true})
  api.nvim_buf_set_keymap(bufnr, 'n', 'N', [[<cmd>lua require'codeql.panel'.change_path(1)<CR>]], { script = true,  silent = true})
  api.nvim_buf_set_keymap(bufnr, 'n', 'f', [[<cmd>lua require'codeql.panel'.label_filter()<CR>]], { script = true,  silent = true})
  api.nvim_buf_set_keymap(bufnr, 'n', '<S-f>', [[<cmd>lua require'codeql.panel'.generic_filter()<CR>]], { script = true,  silent = true})
  api.nvim_buf_set_keymap(bufnr, 'n', '<S-x`>', [[<cmd>lua require'codeql.panel'.clear_filter()<CR>]], { script = true,  silent = true})
end

function M.clear_filter()
  unhide_issues()
  render_content()
end

function M.label_filter()
  local pattern = vim.fn.input("Pattern: ")
  unhide_issues()
  filter_issues("string.match(string.lower(issue.label), string.lower('"..pattern.."')) ~= nil")
  render_content()
end

function M.generic_filter()
  local pattern = vim.fn.input("Pattern: ")
  unhide_issues()
  filter_issues(pattern)
  render_content()
end

function M.toggle_mode()
  if kind ~= "raw" then return end
  local new_mode
  if mode == "tree" then new_mode = "table"
  elseif mode == "table" then new_mode = "tree" end
  M.render({
    issues = issues,
    kind = kind,
    columns = columns,
    mode = new_mode
  })
end

function M.toggle_fold()
  -- prevent highlighting from being off after adding/removing the help text
  vim.cmd('match none')

  local c = vim.fn.line('.')
  local entry
  while c >= 7 do
    entry = line_map[c]
    if entry and (entry.kind == "node" or entry.kind == "issue") and vim.tbl_contains(vim.tbl_keys(entry.obj), "is_folded") then
      entry.obj.is_folded = not entry.obj.is_folded
      render_keep_view(c)
      return
    end
    c = c - 1
  end
end

function M.toggle_help()
  panel_short_help = not panel_short_help
  -- prevent highlighting from being off after adding/removing the help text
  render_keep_view()
end

function M.set_fold_level(level)
  for k, _ in pairs(line_map) do
    line_map[k].obj.is_folded = level
  end
  render_keep_view()
end

function M.change_path(offset)
  local line = vim.fn.line('.') - 1
  if not line_map[line] or line_map[line].kind ~= "issue" then return end

  local issue = line_map[line].obj

  if issue.active_path then
    if issue.active_path == 1 and offset == -1 then
      line_map[line].obj.active_path = #(issue.paths)
    elseif issue.active_path == (#issue.paths) and offset == 1 then
      line_map[line].obj.active_path = 1
    else
      line_map[line].obj.active_path = issue.active_path + offset
    end
    render_keep_view(line+1)
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

function M.jump_to_code(stay_in_pane)
  --print('FDs before jumping '..vim.fn.system('lsof -p '..vim.loop.getpid()..' | wc -l'))
  if not line_map[vim.fn.line('.')] then return end

  local node
  local entry = line_map[vim.fn.line('.')]
  if entry.kind == "issue" then
    node = entry.obj.node
  elseif entry.kind == "node" then
    node = entry.obj
  elseif entry.kind == "row" then
    node = get_column_at_cursor(entry.obj)
  end

  if not node then return end

  if not node.visitable then
    if not not node.filename then util.message(node.filename) end
    return
  end

  -- open from src.zip
  if vim.g.codeql_database and util.is_file(vim.g.codeql_database.sourceArchiveZip) then
    if string.sub(node.filename, 1, 1) == '/' then
      node.filename = string.sub(node.filename, 2)
    end

    -- save audit pane window
    local panel_window = vim.fn.win_getid()

    -- go to main window
    go_to_main_window()

    util.open_from_archive(vim.g.codeql_database.sourceArchiveZip, node.filename)
    vim.fn.execute(node.line)
    -- vim.cmd('normal! z.')
    -- vim.cmd('normal! zv')
    -- vim.cmd('redraw') -- consumes FDs

    -- highlight node
    api.nvim_buf_clear_namespace(0, range_ns, 0, -1)
    local startLine = node.url.startLine
    local startColumn = node.url.startColumn
    local endColumn = node.url.endColumn

     api.nvim_buf_add_highlight(0, range_ns, "CodeqlRange", startLine - 1, startColumn - 1, endColumn)

    -- jump to main window if requested
    if stay_in_pane then vim.fn.win_gotoid(panel_window) end
  elseif not vim.g.codeql_database then
    api.nvim_err_writeln("Please use SetDatabase to point to the analysis database")
  end

  --print('FDs afget jumping '..vim.fn.system('lsof -p '..vim.loop.getpid()..' | wc -l'))
end

function M.open_panel()

  -- check if audit pane is already opened
  if vim.fn.bufwinnr(panel_buffer_name) ~= -1 then
    return
  end

  -- prepare split arguments
  local pos = ''
  if panel_pos == 'right' then
    pos = 'botright'
  elseif panel_pos == 'left' then
    pos = 'topleft'
  else
    util.err_message('Incorrect panel_pos value')
    return
  end

  -- get current win id
  local current_window = vim.fn.win_getid()

  -- go to main window
  go_to_main_window()

  -- split
  vim.fn.execute('silent keepalt '..pos..' vertical '..panel_width..'split '..panel_buffer_name)

  -- go to original window
  vim.fn.win_gotoid(current_window)

  -- buffer options
  local bufnr = vim.fn.bufnr(panel_buffer_name)

  api.nvim_buf_set_option(bufnr, 'filetype', 'codeqlpanel')
  api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  api.nvim_buf_set_option(bufnr, 'bufhidden', 'hide')
  api.nvim_buf_set_option(bufnr, 'swapfile', false)
  api.nvim_buf_set_option(bufnr, 'buflisted', false)

  -- window options
  local win = get_panel_window(panel_buffer_name)
  api.nvim_win_set_option(win, 'wrap', false)
  api.nvim_win_set_option(win, 'number', false)
  api.nvim_win_set_option(win, 'relativenumber', false)
  api.nvim_win_set_option(win, 'foldenable', false)
  api.nvim_win_set_option(win, 'winfixwidth', true)
  api.nvim_win_set_option(win, 'concealcursor', 'nvi')
  api.nvim_win_set_option(win, 'conceallevel', 3)
  api.nvim_win_set_option(win, 'signcolumn', 'yes')
end

function M.close_panel()
  local win = get_panel_window(panel_buffer_name)
  vim.fn.nvim_win_close(win, true)
end

function M.render(opts)
  --  _issues, _kind, _columns)
  M.open_panel()

  line_map = {}
  kind = opts.kind or "raw"
  issues = opts.issues or {}
  columns = opts.columns or {}
  mode = opts.mode

  -- sort
  table.sort(issues, function(a,b)
    if a.rule_id ~= b.rule_id then
      return a.rule_id < b.rule_id
    else
      return a.label < b.label
    end
  end)

  render_content()
end

return M
