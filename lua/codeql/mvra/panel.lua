local NuiTree = require "nui.tree"
local NuiLine = require "nui.line"
local Split = require "nui.split"

local M = {}

M.draw = function(folder, projects)

  local nodes = {}
  table.insert(nodes, NuiTree.Node({ type = "label", label = "MVRA Results" }))
  for nwo, item in pairs(projects) do
    item.type = "result"
    item.path = folder .. "/" .. nwo:gsub("/", "_") .. ".sarif"
    table.insert(nodes, NuiTree.Node(item))
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
      filetype = "codeql_mvra",
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
        line:append("(" .. tostring(node.results_count) .. ")", "Comment")
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
      print(node.path)
      vim.api.nvim_command("LoadSarif " .. node.path)
      return
    end
  end, map_options)

  tree:render()
end

return M
