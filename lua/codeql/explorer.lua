local NuiTree = require "nui.tree"
local NuiLine = require "nui.line"
local Split = require "nui.split"
local Tree = require "codeql.tree"
local config = require "codeql.config"
local util = require "codeql.util"
local devicons = require "nvim-web-devicons"
local vim = vim

local M = {}

M.tree = nil
M.split = nil
M.width = 50

M.prepare_node = function(node)
  if node.type == "label" then
    local line = NuiLine()
    for _, p in ipairs(node.name) do
      line:append(p[1], p[2])
    end
    return line
  end
  local line = NuiLine()
  line:append(string.rep("  ", node:get_depth() - 1))
  if node:has_children() then
    line:append(node:is_expanded() and " " or " ", "SpecialKey")
  end
  if node.type == "dir" then
    line:append(node.name .. "/", "SpecialKey")
  else
    local name = vim.fn.split(node.name, "\\.")[1]
    local ext = vim.fn.split(node.name, "\\.")[2]
    local icon, hl = devicons.get_icon(name, ext)
    icon = icon or ""
    line:append(icon .. " ", hl)
    line:append(node.name)
  end
  return line
end

M.create_tree = function()
  M.tree = NuiTree {
    winid = M.split.winid,
    get_node_id = function(node)
      return node.id
    end,
    prepare_node = M.prepare_node,
  }
end

M.create_nodes = function(source_items, level)
  level = level or 0
  local nodes = {}
  local indent = ""
  local indent_size = 2
  for _ = 1, level do
    for _ = 1, indent_size do
      indent = indent .. " "
    end
  end

  for _, item in ipairs(source_items) do
    local nodeData = {
      id = item.id,
      name = item.name,
      type = item.type,
      indent = indent,
    }

    local node_children = nil
    if item.children ~= nil then
      node_children = M.create_nodes(item.children, level + 1)
    end

    local node = NuiTree.Node(nodeData, node_children)
    if item._is_expanded then
      node:expand()
    end
    table.insert(nodes, node)
  end
  return nodes
end

M.create_split = function()
  if not util.is_blank(M.split) then
    M.width = vim.api.nvim_win_get_width(M.split.winid)
    M.split:unmount()
  end
  local split = Split {
    relative = "win",
    position = "left",
    size = M.width,
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
      filetype = "codeql_explorer",
    },
  }
  split:mount()

  local map_options = { noremap = true, nowait = true }

  split:map("n", "q", function()
    split:unmount()
  end, { noremap = true })

  split:map("n", "<CR>", function()
    local node = M.tree:get_node()
    if node.type == "label" then
      return
    end
    local target_winid = require("window-picker").pick_window()
    vim.api.nvim_set_current_win(target_winid)
    local filename = string.format("%s/%s", config.database.sourceLocationPrefix, node.id)
    local bufname = string.format("ql:/%s", filename)
    if vim.fn.bufnr(bufname) > -1 then
      vim.api.nvim_command(string.format("buffer %s", bufname))
    else
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, bufname)
      filename = string.sub(filename, 2)
      util.open_from_archive(bufnr, filename, { target_winid = target_winid })
    end
  end, map_options)

  split:map("n", "o", function()
    local node = M.tree:get_node()

    if node.type == "dir" then
      if node:is_expanded() then
        if node:collapse() then
          M.tree:render()
        end
      else
        if node:expand() then
          M.tree:render()
        end
      end
    else
      -- make `o` close file's parent
      if node.type == "file" then
        local parent = M.tree:get_node(node:get_parent_id())
        if parent:collapse() then
          M.tree:render()
        end
      end
    end
  end, map_options)

  M.split = split
end

M.draw = function()
  local db = config.database
  if not db then
    util.err_message "Missing database. Use :SetDatabase command"
    return
  else
    local files = util.list_from_archive(db.sourceArchiveZip)
    local db_name = vim.split(db.path, "/")[#vim.split(db.path, "/") - 1]
    local root = Tree:new("root", "root", "dir", {
      Tree:new("::header1::", { { "🛢 ", "SpecialKey" }, { db_name } }, "label"),
      Tree:new("::header2::", { { "" } }, "label"),
    })
    for _, file in ipairs(files) do
      local segments = vim.fn.split(file, "/")
      local current = root
      for i, segment in ipairs(segments) do
        local sublist = { unpack(segments, 1, i) }
        local id = table.concat(sublist, "/")
        local type = #segments == i and "file" or "dir"
        local node = current(id, segment, type)
        current = node
      end
    end

    local flatten_root = root:flatten_directories()

    local nui_nodes = M.create_nodes(flatten_root.children)
    M.create_split()
    M.create_tree()
    M.tree:set_nodes(nui_nodes)
    M.tree:render()
  end
end

return M
