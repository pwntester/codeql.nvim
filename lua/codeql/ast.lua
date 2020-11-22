local api = vim.api
local format = string.format
local util = require'codeql.util'

local codeql_ast_ns = api.nvim_create_namespace('codeql_ast')

local M = {}

M._entries = setmetatable({}, {
  __index = function(tbl, key)
    local entry = rawget(tbl, key)

    if not entry then
      entry = {}
      rawset(tbl, key, entry)
    end

    return entry
  end
})

local function is_valid_graph(props)
  for _, prop in ipairs(props.tuples) do
    if prop[1] == 'semmle.graphKind' and prop[2] == 'tree' then
      return true
    end
  end
  return false
end

local function is_buf_visible(bufnr)
  local windows = vim.fn.win_findbuf(bufnr)
  return #windows > 0
end

local function close_buf_windows(bufnr)
  if not bufnr then return end

  util.for_each_buf_window(bufnr, function(window)
    api.nvim_win_close(window, true)
  end)
end

local function close_buf(bufnr)
  if not bufnr then return end

  close_buf_windows(bufnr)

  if api.nvim_buf_is_loaded(bufnr) then
    vim.cmd(format("bw! %d", bufnr))
  end
end

local function clear_entry(bufnr)
  local entry = M._entries[bufnr]

  close_buf(entry.display_bufnr)
  close_buf(entry.query_bufnr)
  M._entries[bufnr] = nil
end

local function setup_buf(for_buf)
  if M._entries[for_buf].display_bufnr then
    return M._entries[for_buf].display_bufnr
  end

  local buf = api.nvim_create_buf(false, false)

  api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  api.nvim_buf_set_option(buf, 'swapfile', false)
  api.nvim_buf_set_option(buf, 'buflisted', false)
  api.nvim_buf_set_option(buf, 'filetype', 'codeqlast')

  vim.cmd(format('augroup CodeQLAST_%d', buf))
  vim.cmd 'au!'
  vim.cmd(format([[autocmd CursorMoved <buffer=%d> lua require'codeql.ast'.highlight_node(%d)]], buf, for_buf))
  vim.cmd(format([[autocmd BufLeave <buffer=%d> lua require'codeql.ast'.clear_highlights(%d)]], buf, for_buf))
  vim.cmd(format([[autocmd BufWinEnter <buffer=%d> lua require'codeql.ast'.update(%d)]], buf, for_buf))
  vim.cmd 'augroup END'

  api.nvim_buf_set_keymap(buf, 'n', 'R', format(':lua require "codeql.ast".update(%d)<CR>', for_buf), { silent = true })
  api.nvim_buf_set_keymap(buf, 'n', '<CR>', format(':lua require "codeql.ast".goto_node(%d)<CR>', for_buf), { silent = true })
  api.nvim_buf_attach(buf, false, {
    on_detach = function() clear_entry(for_buf) end
  })

  return buf
end

local function print_node(bufnr, node, lines, level)

  -- keep track of what nodes are printed in each line
  M._entries[bufnr].tree2buf[#lines + 1] = node
  node.line = #lines

  -- print node
  local line = format(
    '%s%s [%d, %d] - [%d, %d]',
    string.rep(' ', 2 * level),
    node.label ~= '' and node.label or '???',
    node.location.startLine,
    node.location.startColumn,
    node.location.endLine,
    node.location.endColumn)
  line = string.gsub(line, '\n', '')
  table.insert(lines, line)

  -- print each child
  if #node.children > 0 then
    for _, child in ipairs(node.children) do
      print_node(bufnr, child, lines, level + 1)
    end
  end
end

local function print_tree(bufnr, roots)
  M._entries[bufnr].tree2buf = {}
  local lines = {}
  for _, root in ipairs(roots) do
    print_node(bufnr, root, lines, 0)
  end
  return lines
end

local function sort_node(node)
  table.sort(node.children, function (left, right)
    return left.order < right.order
  end)
  if #node.children > 0 then
    for _, child in ipairs(node.children) do
      sort_node(child)
    end
  end
end

local function sort_tree(roots)
  table.sort(roots, function (left, right)
    return left.order < right.order
  end)
  for _, root in ipairs(roots) do
    sort_node(root)
  end
end

local function is_cursor_in_node(cursor, node)

  local start_row = node.location.startLine
  local start_col = node.location.startColumn
  local end_row = node.location.endLine
  local end_col = node.location.endColumn
  local cursor_row = cursor[1]
  local cursor_col = cursor[2] + 1

  -- print(format('(%d,%d) in [%d,%d] - [%d-%d]?',
  --   cursor_row, cursor_col,
  --   start_row, start_col,
  --   end_row, end_col))

  if cursor_row < start_row or cursor_row > end_row then
    return false
  elseif cursor_row > start_row and cursor_row < end_row then
    return true
  elseif start_row == end_row then
    return cursor_col >= start_col and cursor_col <= end_col
  elseif end_row > start_row then
    if cursor_row == start_row then
      return cursor_col >= start_col
    elseif cursor_row == end_row then
      return cursor_col <= end_col
    end
  end
  util.err_message('Error checking cursor position')
end

local function get_node_at_cursor(cursor, node, matching_nodes)
  if is_cursor_in_node(cursor, node) then
    table.insert(matching_nodes, node)
  end
  if #node.children > 0 then
    for _, child in ipairs(node.children) do
      get_node_at_cursor(cursor, child, matching_nodes)
    end
  end
end

-- exported functions

function M.clear_highlights(bufnr, namespace)
  if not bufnr then return end
  namespace = namespace or codeql_ast_ns
  api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
end

function M.clear_ast_highlights(bufnr)
  M.clear_highlights(M._entries[bufnr].display_bufnr)
end

function M.highlight_ast_nodes(bufnr, nodes)
  local entry = M._entries[bufnr]
  local results = entry.results
  local display_buf = entry.display_bufnr
  local lines = {}

  if not results or not display_buf then return end

  for _, node in ipairs(nodes) do
    local lnum = node.line
    table.insert(lines, lnum)
    local ast_lines = api.nvim_buf_get_lines(display_buf, lnum, lnum+1, false)
    if ast_lines[1] then
      local _, _, ws, _ = string.find(ast_lines[1], '(%s*)(.+)')
      vim.api.nvim_buf_add_highlight(display_buf, codeql_ast_ns, 'CodeqlAstFocus', lnum, #ws, -1)
    end
  end

  return lines
end

function M.highlight_node(bufnr)
  M.clear_highlights(bufnr)

  local node = M._entries[bufnr].tree2buf[vim.fn.line('.')]

  if not node then return end

  local loc = node.location
  local start_row = loc.startLine
  local start_col = loc.startColumn
  local end_row = loc.endLine
  local end_col = loc.endColumn
  vim.highlight.range(bufnr, codeql_ast_ns, 'CodeqlAstFocus', {start_row-1, start_col-1}, {end_row-1, end_col})

  util.for_each_buf_window(bufnr, function(window)
    pcall(api.nvim_win_set_cursor, window, { start_row, start_col })
  end)
end

function M.goto_node(bufnr)
  local line = vim.fn.line(".")
  local node = M._entries[bufnr].tree2buf[line]
  local loc = node.location

  local bufwin = vim.fn.win_findbuf(bufnr)[1]
  if bufwin then
    api.nvim_set_current_win(bufwin)
    M.clear_highlights(bufnr)
    api.nvim_win_set_cursor(bufwin, { loc.startLine, loc.startColumn })
  end
end

function M.open(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local display_buf = setup_buf(bufnr)
  local current_window = api.nvim_get_current_win()

  M._entries[bufnr].display_bufnr = display_buf
  vim.cmd "vsplit"
  vim.cmd(format("buffer %d", display_buf))

  api.nvim_win_set_option(0, 'spell', false)
  api.nvim_win_set_option(0, 'number', false)
  api.nvim_win_set_option(0, 'relativenumber', false)
  api.nvim_win_set_option(0, 'cursorline', false)

  api.nvim_set_current_win(current_window)

  return display_buf
end

function M.update(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local display_buf = M._entries[bufnr].display_bufnr

  -- Don't bother updating if the playground isn't shown
  if not display_buf or not is_buf_visible(display_buf) then return end

  local results = M._entries[bufnr].results

  api.nvim_buf_set_lines(display_buf, 0, -1, false, results.lines)
  -- if print_virt_hl then
  --   printer.print_hl_groups(bufnr, display_buf)
  -- end
end

function M.toggle(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local display_buf = M._entries[bufnr].display_bufnr

  if display_buf and is_buf_visible(display_buf) then
    close_buf_windows(M._entries[bufnr].query_bufnr)
    close_buf_windows(display_buf)
  else
    M.open(bufnr)
  end
end

function M.highlight_ast_node_from_buffer(bufnr)
  M.clear_ast_highlights(bufnr)

  local display_buf = M._entries[bufnr].display_bufnr
  if not display_buf then return end

  local bufwin = vim.fn.win_findbuf(bufnr)[1]
  if not bufwin then bufwin = api.nvim_get_current_win() end
  if bufwin then
    local cursor = api.nvim_win_get_cursor(bufwin)
    local roots = M._entries[bufnr].roots

    local nodes_at_cursor = {}
    for _, root in ipairs(roots) do
      get_node_at_cursor(cursor, root, nodes_at_cursor)

      -- if we already found a root with nodes at cursor, skip the rest
      if #nodes_at_cursor > 0 then break end
    end

    if #nodes_at_cursor == 0 then return end

    local lnums = M.highlight_ast_nodes(bufnr, nodes_at_cursor)
    if lnums[#lnums] then
      util.for_each_buf_window(display_buf, function(window)
        pcall(api.nvim_win_set_cursor, window, { lnums[#lnums], 0 })
      end)
    end
  end
end

M._highlight_ast_node_debounced = util.debounce(M.highlight_ast_node_from_buffer, function()
  return 25
end)

function M.attach(bufnr)
  vim.cmd(format('augroup CodeQLAST %d', bufnr))
  vim.cmd 'au!'
  vim.cmd(format([[autocmd CursorMoved <buffer=%d> lua require'codeql.ast'._highlight_ast_node_debounced(%d)]], bufnr, bufnr))
  vim.cmd(format([[autocmd BufLeave <buffer=%d> lua require'codeql.ast'.clear_ast_highlights(%d)]], bufnr, bufnr))
  vim.cmd 'augroup END'
end

function M.detach(bufnr)
  clear_entry(bufnr)
  vim.cmd(format('autocmd! CodeQLAST_%d CursorMoved', bufnr))
  vim.cmd(format('autocmd! CodeQLAST_%d BufLeave', bufnr))
end

function M.build_ast(jsonPath, bufnr)
  if not util.is_file(jsonPath) then return end
  local results = util.read_json_file(jsonPath)

  local nodeTuples = results.nodes
  local edgeTuples = results.edges
  local graphProperties = results.graphProperties

  if not is_valid_graph(graphProperties) then
    util.err_message('Invalid AST tree')
    return
  end

  local idToItem = {}
  local parentToChildren = {}
  local childToParent = {}
  local astOrder = {}
  local roots = {}

  -- Build up the parent-child relationships
  for _, tuple in ipairs(edgeTuples.tuples) do
    local source, target, tupleType, orderValue = unpack(tuple)
    -- local target = tuple[2]
    -- local tupleType = tuple[3]
    -- local orderValue = tuple[4]
    local sourceId = source.id
    local targetId = target.id

    if tupleType == 'semmle.order' then
      astOrder[targetId] = tonumber(orderValue)
    elseif tupleType == 'semmle.label' then
      childToParent[targetId] = sourceId
      local children = parentToChildren[sourceId] or {}
      table.insert(children, targetId)
      parentToChildren[sourceId] = children
    else
      -- ignore other tupleTypes since they are not needed by the ast viewer
    end
  end

  -- populate parents and children
  for _, tuple in ipairs(nodeTuples.tuples) do
    local entity, tupleType, value = unpack(tuple)
    -- local tupleType = tuple[2]
    -- local orderValue = tuple[3]
    local id = entity.id

    if tupleType == 'semmle.order' then
      astOrder[id] = tonumber(value)
    elseif tupleType == 'semmle.label' then
      local item = {
        id = id;
        label = value and value or entity.label;
        location = entity.url;
        children = {};
        order = math.huge;
      }

      idToItem[id] = item
      local parent = idToItem[childToParent[id] or -1]
      if parent then
        local astItem = item
        astItem.parent = parent;
        table.insert(parent.children, astItem)
      end

      local children = parentToChildren[id] or {}
      for _, childId in ipairs(children) do
        local child = idToItem[childId]
        if child then
          child.parent = item
          table.insert(item.children, child)
        end
      end
    else
      -- ignore other tupleTypes since they are not needed by the ast viewer
    end
  end

  -- find the roots and add the order
  for _, item in pairs(idToItem) do
    item.order = astOrder[item.id] and astOrder[item.id] or math.huge
    if not item.parent then
      table.insert(roots, item)
    end
  end

  sort_tree(roots)

  print("found "..#roots.." roots")

  M.attach(bufnr)
  local text_lines = print_tree(bufnr, roots)
  M._entries[bufnr].roots = roots
  M._entries[bufnr].results = { lines = text_lines }
  M.open(bufnr)
end

return M
