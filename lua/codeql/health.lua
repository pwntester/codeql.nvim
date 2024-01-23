local health = vim.health or require "health"
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error
local info = health.info or health.report_info

local dependencies = {
  { lib = "plenary" },
  { name = "nui", lib = "nui.popup" },
  { lib = "telescope" },
  { lib = "nvim-web-devicons" },
  { name = "nvim-window-picker", lib = "window-picker" },
}

local binaries = {
  { name = "codeql", cli = { "codeql", "--version" } },
  { name = "gh", cli = { "gh", "--version" } },
  { name = "mrva", cli = { "gh", "mrva", "--help" } },
}

local M = {}

function M.check_dependencies()
  start "Checking plugins requirements"

  for _, plugin in ipairs(dependencies) do
    local result, _ = pcall(require, plugin.lib)
    local optional = plugin.optional or false
    local name = plugin.name or plugin.lib

    if result and not optional then
      ok("Installed plugin: " .. name)
    elseif not result and optional == true then
      warn("Optional plugin not installed: " .. name)
    else
      error("Required plugin missing: " .. name)
    end
  end
end

--- Check if the given command is available
---@param cmds table
---@return boolean
function M.check_cli(cmds)
  local result = false

  if vim.fn.executable(cmds[1]) == 1 then
    local cli = table.concat(cmds, " ")
    local status, output = pcall(vim.fn.system, cli)

    if status and output ~= "" then
      result = true
    end
  end

  return result
end

function M.check_binaries()
  start "Check installed binaries"

  for _, binary in ipairs(binaries) do
    -- run and check the command
    local cmds = binary.cli or { binary.name }
    local optional = binary.optional or false

    local result = M.check_cli(cmds)

    if result and not optional then
      ok("Installed binary: " .. binary.name)
    elseif not result and not optional then
      warn("Optional binary not installed: " .. binary.name)
    else
      error("Required binary missing: " .. binary.name)
    end
  end
end

--- Health Check
function M.check()
  M.check_dependencies()
  M.check_binaries()
end

return M
