local health = vim.health or require "health"
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error
local info = health.info or health.report_info

local _, Job = pcall(require, "plenary.job")

local dependencies = {
  { lib = "plenary" },
  { name = "nui", lib = "nui.popup" },
  { lib = "telescope" },
  { lib = "nvim-web-devicons" },
  { name = "nvim-window-picker", lib = "window-picker" },
}

local binaries = {
  { name = "codeql", command = "codeql", args = { "--version" } },
  { name = "gh", command = "gh", args = { "--version" } },
  { name = "mrva", command = "gh", args = { "mrva", "help" }, optional = true },
}

local M = {}

function M.check_dependencies()
  start "Checking plugins requirements"

  for _, plugin in ipairs(dependencies) do
    local result, _ = pcall(require, plugin.lib)
    local optional = plugin.optional or false
    local name = plugin.name or plugin.lib

    if result then
      ok("Installed plugin: " .. name)
    elseif not result and optional == true then
      warn("Optional plugin not installed: " .. name)
    else
      error("Required plugin missing: " .. name)
    end
  end
end

--- Check if the given command is available
---@param binary table
---@return boolean
function M.check_cli(binary)
  local result = false

  if vim.fn.executable(binary.command) == 1 then
    -- run command and test if the exit code is 0
    local job = Job:new {
      enable_recording = true,
      command = binary.command,
      args = binary.args or {},
      on_exit = function(_, code)
        result = code == 0
      end,
    }
    job:start()
    job:wait()
  end

  return result
end

function M.check_binaries()
  start "Check installed binaries"

  for _, binary in ipairs(binaries) do
    -- run and check the command
    local optional = binary.optional or false

    local result = M.check_cli(binary)

    if result == true then
      ok("Installed binary: " .. binary.name)
    elseif result == false and optional == true then
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
