local _, Job = pcall(require, "plenary.job")
local util = require "codeql.util"
local uv = vim.loop

local M = {}

local env_vars = {
  PATH = vim.env["PATH"],
  GH_CONFIG_DIR = vim.env["GH_CONFIG_DIR"],
  GITHUB_TOKEN = vim.env["GITHUB_TOKEN"],
  XDG_CONFIG_HOME = vim.env["XDG_CONFIG_HOME"],
  XDG_DATA_HOME = vim.env["XDG_DATA_HOME"],
  XDG_STATE_HOME = vim.env["XDG_STATE_HOME"],
  AppData = vim.env["AppData"],
  LocalAppData = vim.env["LocalAppData"],
  HOME = vim.env["HOME"],
  NO_COLOR = 1,
  http_proxy = vim.env["http_proxy"],
  https_proxy = vim.env["https_proxy"],
}

function M.run(opts)
  opts = opts or {}
  if opts.headers then
    for _, header in ipairs(opts.headers) do
      table.insert(opts.args, "-H")
      table.insert(opts.args, header)
    end
  end
  -- M.buf_to_stdin("gh", opts.args, function(stderr, output)
  --   opts.cb(output, stderr)
  -- end)
  local job = Job:new {
    enable_recording = true,
    command = "gh",
    args = opts.args,
    env = env_vars,
    on_exit = vim.schedule_wrap(function(j_self)
      local output = table.concat(j_self:result(), "\n")
      local stderr = table.concat(j_self:stderr_result(), "\n")
      opts.cb(output, stderr)
    end),
  }
  job:start()
end

function M.download(opts)
  M.buf_to_stdin("gh", { "api", opts.url }, function(stderr, output)
    if not util.is_blank(stderr) then
      vim.api.nvim_err_writeln(stderr)
    elseif not util.is_blank(output) then
      print("size: " .. #output)
      local file = io.open(opts.path, "w")
      io.output(file)
      io.write(output)
      io.close(file)
      opts.cb(opts.path)
    else
      vim.api.nvim_err_writeln "No output"
    end
  end)
end

local close_handle = function(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

function M.buf_to_stdin(cmd, args, handler)
  print(cmd, table.concat(args, " "))
  local output = ""
  local stderr_output = ""

  local handle_stdout = vim.schedule_wrap(function(err, chunk)
    if err then
      error("stdout error: " .. err)
    end

    if chunk then
      output = output .. chunk
    end
    if not chunk then
      handler(stderr_output ~= "" and stderr_output or nil, output)
    end
  end)

  local handle_stderr = function(err, chunk)
    if err then
      error("stderr error: " .. err)
    end
    if chunk then
      stderr_output = stderr_output .. chunk
    end
  end

  local stdin = uv.new_pipe(true)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local stdio = { stdin, stdout, stderr }

  local handle
  handle = uv.spawn(cmd, { args = args, stdio = stdio }, function()
    stdout:read_stop()
    stdout:read_stop()

    close_handle(stdin)
    close_handle(stdout)
    close_handle(stderr)
    close_handle(handle)
  end)

  uv.read_start(stdout, handle_stdout)
  uv.read_start(stderr, handle_stderr)

  -- specific implementation is probably irrelevant, since this part is working OK
  --stdin:write(buffer_to_string(), function() stdin:close() end)
end

return M
