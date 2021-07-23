local uv = vim.loop
local api = vim.api
local schedule = vim.schedule
local format = string.format

local M = {}

M.client = nil

local function start()

  print("Starting CodeQL CLI Server")

  local cmd = "codeql"
  local cmd_args = {"execute", "cli-server", "--logdir", "/tmp/codeql_queryserver"}

  if not (vim.fn.executable(cmd) == 1) then
    api.nvim_err_writeln(format("The given command %q is not executable.", cmd))
  end

  local stdin = uv.new_pipe(false)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  local handle, pid
  do
    local function onexit(_, _)
      stdin:close()
      stdout:close()
      stderr:close()
      handle:close()
    end
    local spawn_params = {
      args = cmd_args;
      stdio = {stdin, stdout, stderr};
    }
    handle, pid = uv.spawn(cmd, spawn_params, onexit)
  end

  local callback
  local stdoutBuffers = {}

  local function request(cmd, cb)
    callback = cb
    if handle:is_closing() then return false end
    schedule(function()
      local encoded = assert(vim.fn.json_encode(cmd))
      stdin:write(encoded)
      stdin:write(string.char(0))
    end)
    return true
  end

  stderr:read_start(function(err, data)
    assert(not err, err)
    print("CLISERVER STDERR: "..data)
  end)

  stdout:read_start(function(err, data)
    assert(not err, err)
    if data and #data> 0 and string.byte(data, #data, #data) == 0 then
      table.insert(stdoutBuffers, string.sub(data, 1, #data-1))
      callback(vim.trim(table.concat(stdoutBuffers)))
      stdoutBuffers = {}
    elseif data then
      table.insert(stdoutBuffers, data)
    end
  end)

  return {
    handle = handle;
    pid = pid;
    request = request;
  }
end

function M.runAsync(cmd, callback)
  if not M.client then
    M.client = start()
  end
  M.client.request(cmd, callback)
end

function M.runSync(cmd)
  local timeout = 15000
  local done = false
  local result
  M.runAsync(cmd, function (res)
    result = res
    done = true
  end)
  local wait_result = vim.wait(timeout, function()
    vim.cmd [[redraw!]]
    return done
  end, 200)
  if not wait_result then
    print(format("'%s' was unable to complete in %s ms",
      table.concat(cmd, ' '),
      timeout
    ))
    return nil
  else
    return result
  end
end

function M.shutdownServer()
  M.runAsync({"shutdown"}, function(_)
    print('Shutting down')
  end)
end

--M.runAsync({"resolve", "library-path", "-v", "--log-to-stderr", "--format=json", "--query=/Users/pwntester/Research/projects/bean_validation/onedev/attack_surface.ql", "--search-path=/Users/pwntester/codeql-home/codeql-repo", "--search-path=/Users/pwntester/codeql-home/codeql-go-repo", "--search-path=/Users/pwntester/codeql-home/pwntester-repo"}, function(res) print(res) end)
--M.runAsync({"resolve", "database", "-v", "--log-to-stderr", "--format=json", "/Users/pwntester/Research/projects/bean_validation/onedev/codeql_db/"}, function(res) print(res) end)
--M.runAsync({"resolve", "database", "-v", "--log-to-stderr", "--format=json", "/Users/pwntester/Research/projects/bean_validation/onedev/codeql_db/"}, function(res) print(res) end)
return M
