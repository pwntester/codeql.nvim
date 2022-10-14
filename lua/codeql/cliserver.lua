local M = {}

M.client = nil

local function start()
  local util = require("codeql.util")
  util.message("Starting CodeQL CLI Server")

  local cmd = "codeql"
  local cmd_args = { "execute", "cli-server", "--logdir", "/tmp/codeql_queryserver" }

  if not (vim.fn.executable(cmd) == 1) then
    require("codeql.util").err_message(string.format("The given command %q is not executable.", cmd))
  end

  local stdin = vim.loop.new_pipe(false)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  local handle, pid
  do
    local function onexit(_, _)
      stdin:close()
      stdout:close()
      stderr:close()
      handle:close()
    end

    local spawn_params = {
      args = cmd_args,
      stdio = { stdin, stdout, stderr },
    }
    handle, pid = vim.loop.spawn(cmd, spawn_params, onexit)
  end

  local callback
  local stdoutBuffers = {}

  local function request(c, cb)
    callback = cb
    if handle:is_closing() then
      return false
    end
    vim.schedule(function()
      local encoded = assert(vim.fn.json_encode(c))
      stdin:write(encoded)
      stdin:write(string.char(0))
    end)
    return true
  end

  stderr:read_start(function(err, data)
    assert(not err, err)
    vim.schedule(function()
      if data then
        require("codeql.util").err_message("cliserver error: " .. data)
      end
    end)
  end)

  stdout:read_start(function(err, data)
    assert(not err, err)
    if data and #data > 0 and string.byte(data, #data, #data) == 0 then
      table.insert(stdoutBuffers, string.sub(data, 1, #data - 1))
      callback(vim.trim(table.concat(stdoutBuffers)))
      stdoutBuffers = {}
    elseif data then
      table.insert(stdoutBuffers, data)
    end
  end)

  return {
    handle = handle,
    pid = pid,
    request = request,
  }
end

function M.runAsync(cmd, callback)
  if not M.client then
    M.client = start()
  end
  M.client.request(cmd, callback)
end

function M.runSync(cmd)
  local util = require("codeql.util")
  local timeout = require("codeql.config").get_config().job_timeout
  local done = false
  local result
  M.runAsync(cmd, function(res)
    result = res
    done = true
  end)
  local wait_result = vim.wait(timeout, function()
    vim.cmd [[redraw!]]
    return done
  end, 200)
  if not wait_result then
    util.message(string.format("'%s' was unable to complete in %s ms", table.concat(cmd, " "), timeout))
    return nil
  else
    return result
  end
end

function M.shutdownServer()
  M.runAsync({ "shutdown" }, function(_)
    print "Shutting down"
  end)
end

--M.runAsync({"resolve", "library-path", "-v", "--log-to-stderr", "--format=json", "--query=/Users/pwntester/Research/projects/bean_validation/onedev/attack_surface.ql", "--search-path=/Users/pwntester/codeql-home/codeql-repo", "--search-path=/Users/pwntester/codeql-home/codeql-go-repo", "--search-path=/Users/pwntester/codeql-home/pwntester-repo"}, function(res) print(res) end)
--M.runAsync({"resolve", "database", "-v", "--log-to-stderr", "--format=json", "/Users/pwntester/Research/projects/bean_validation/onedev/codeql_db/"}, function(res) print(res) end)
--M.runAsync({"resolve", "database", "-v", "--log-to-stderr", "--format=json", "/Users/pwntester/Research/projects/bean_validation/onedev/codeql_db/"}, function(res) print(res) end)
return M
