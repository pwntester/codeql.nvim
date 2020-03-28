local rpc = require 'vim.lsp.rpc'
local vim = vim
local validate = vim.validate

local client_index = 0
local function next_client_id()
  client_index = client_index + 1
  return client_index
end

local function optional_validator(fn)
  return function(v)
    return v == nil or fn(v)
  end
end

local function validate_client_config(config)
  validate {
    config = { config, 't' };
  }
  -- validate {
  --   root_dir        = { config.root_dir, is_dir, "directory" };
  --   callbacks       = { config.callbacks, "t", true };
  --   capabilities    = { config.capabilities, "t", true };
  --   cmd_cwd         = { config.cmd_cwd, optional_validator(is_dir), "directory" };
  --   cmd_env         = { config.cmd_env, "t", true };
  --   name            = { config.name, 's', true };
  --   on_error        = { config.on_error, "f", true };
  --   on_exit         = { config.on_exit, "f", true };
  --   on_init         = { config.on_init, "f", true };
  --   before_init     = { config.before_init, "f", true };
  --   offset_encoding = { config.offset_encoding, "s", true };
  -- }
  local cmd, cmd_args = cmd_parts(config.cmd)
  -- local offset_encoding = valid_encodings.UTF16
  -- if config.offset_encoding then
  --   offset_encoding = validate_encoding(config.offset_encoding)
  -- end
  return {
    cmd = cmd; 
    cmd_args = cmd_args;
    offset_encoding = offset_encoding;
  }
end

local M = {}

function M.start_client(config)
  local cleaned_config = validate_client_config(config)
  local cmd, cmd_args, offset_encoding = cleaned_config.cmd, cleaned_config.cmd_args, cleaned_config.offset_encoding

  local client_id = next_client_id()

  local callbacks = config.callbacks or {}
  local name = config.name or tostring(client_id)
  local log_prefix = string.format("LSP[%s]", name)
  local handlers = {}

  local function resolve_callback(method)
    return callbacks[method] or default_callbacks[method]
  end

  function handlers.notification(method, params)
    local _ = log.debug() and log.debug('notification', method, params)
    local callback = resolve_callback(method)
    if callback then
      -- Method name is provided here for convenience.
      callback(nil, method, params, client_id)
    end
  end

  function handlers.server_request(method, params)
    local _ = log.debug() and log.debug('server_request', method, params)
    local callback = resolve_callback(method)
    if callback then
      local _ = log.debug() and log.debug("server_request: found callback for", method)
      return callback(nil, method, params, client_id)
    end
    local _ = log.debug() and log.debug("server_request: no callback found for", method)
    return nil, rpc.rpc_response_error(protocol.ErrorCodes.MethodNotFound)
  end

  function handlers.on_error(code, err)
    local _ = log.error() and log.error(log_prefix, "on_error", { code = rpc.client_errors[code], err = err })
    err_message(log_prefix, ': Error ', rpc.client_errors[code], ': ', vim.inspect(err))
    if config.on_error then
      local status, usererr = pcall(config.on_error, code, err)
      if not status then
        local _ = log.error() and log.error(log_prefix, "user on_error failed", { err = usererr })
        err_message(log_prefix, ' user on_error failed: ', tostring(usererr))
      end
    end
  end

  function handlers.on_exit(code, signal)
    if config.on_exit then
      pcall(config.on_exit, code, signal)
    end
  end

  -- Start the RPC client.
  return rpc.start(cmd, cmd_args, handlers, {
    cwd = config.cmd_cwd;
    env = config.cmd_env;
  })
end

local function cmd_parts(input)
  local cmd, cmd_args
  if vim.tbl_islist(input) then
    cmd = input[1]
    cmd_args = {}
    -- Don't mutate our input.
    for i, v in ipairs(input) do
      assert(type(v) == 'string', "input arguments must be strings")
      if i > 1 then
        table.insert(cmd_args, v)
      end
    end
  else
    error("cmd type must be list.")
  end
  return cmd, cmd_args
end

local function err_message(...)
  nvim_err_writeln(table.concat(vim.tbl_flatten{...}))
  nvim_command("redraw")
end

local function validate_encoding(encoding)
  validate {
    encoding = { encoding, 's' };
  }
  return valid_encodings[encoding:lower()]
      or error(string.format("Invalid offset encoding %q. Must be one of: 'utf-8', 'utf-16', 'utf-32'", encoding))
end

function M.stop_client(client, force)
  local handle = client.handle
  if handle:is_closing() then
    return
  end
  if force then
    handle:kill(15)
    return
  end
  -- Sending a signal after a process has exited is acceptable.
  client.request('shutdown', nil, function(err, _)
    if err == nil then
      client.notify('exit')
    else
      -- If there was an error in the shutdown request, then term to be safe.
      handle:kill(15)
    end
  end)
end

local config = {
    cmd             = {"codeql", "execute", "query-server"};
    offset_encoding = {"utf-8", "utf-16"};
}

local client = M.start_client(config)

client.request(method, params, function(err, result)
  callback(err, method, result, client_id)
end)


M.stop_client(client, false)

return M
-- vim:sw=2 ts=2 et
