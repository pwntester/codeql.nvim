local util = require 'ql.util'
local job = require 'ql.job'
local rpc = require 'vim.lsp.rpc'
local vim = vim
local validate = vim.validate

local client_index = 0
local function next_client_id()
  client_index = client_index + 1
  return client_index
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

local function optional_validator(fn)
  return function(v)
    return v == nil or fn(v)
  end
end

-- TODO: fix this and use similar validation for start_client
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
    return callbacks[method] -- or default_callbacks[method]
  end

  function handlers.notification(method, params)
    local callback = resolve_callback(method)
    if callback then
      -- Method name is provided here for convenience.
      callback(method, params, client_id)
    end
  end

  function handlers.server_request(method, params)
    local callback = resolve_callback(method)
    if callback then
      return callback(method, params, client_id)
    end
    return nil, rpc.rpc_response_error(protocol.ErrorCodes.MethodNotFound)
  end

  function handlers.on_error(code, err)
    err_message(log_prefix, ': Error ', rpc.client_errors[code], ': ', vim.inspect(err))
    if config.on_error then
      local status, usererr = pcall(config.on_error, code, err)
      if not status then
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

local clients = {}

function M.start_server(buf)
  if clients[buf] then
    print("Query Server already started for buffer "..buf)
    return clients[buf]
  end
  local config = {
      cmd             = {"codeql", "execute", "query-server", "--logdir", "/tmp/codeql"};
      offset_encoding = {"utf-8", "utf-16"};
      callbacks = {
        ['ql/progressUpdated'] = function(method, params, client_id)
          print(params.message)
        end;
        ['evaluation/queryCompleted'] = function(method, params, client_id)
          -- if ok, return {}, else return error (eg rpc.rpc_response_error(protocol.ErrorCodes.MethodNotFound))
          return {}
        end
      }
  }
  local client = M.start_client(config)
  clients[buf] = client
  return client
end

function M.run_query(config)
  local client = nil
  if clients[config.buf] then
    client = clients[config.buf]
  else
    client = M.start_server(config.buf)
    clients[config.buf] = client
  end
  local queryPath = config.query
  local dbPath = config.db
  local qloPath = vim.fn.tempname()
  local resultsPath = vim.fn.tempname()

  local json = util.runcmd('codeql resolve library-path --format=json --query='..queryPath, true) 
  local decoded, err = util.json_decode(json)
  if not decoded then
      print("Error resolving library path: "..err)
      return
  end
  local libraryPath = decoded.libraryPath

  local dbDir = dbPath
  for _, dir in ipairs(vim.fn.glob(vim.fn.fnameescape(dbPath)..'*', 1, 1)) do 
    if util.starts_with(dir, dbPath..'db-') then
      dbDir = dir
      break
    end
  end
  local dbScheme = decoded.dbscheme

  -- https://github.com/github/vscode-codeql/blob/master/extensions/ql-vscode/src/messages.ts
  local params = {
    body = {
      compilationOptions = {
        computeNoLocationUrls = true;
        failOnWarnings = false;
        fastCompilation = false;
        includeDilInQlo = true;
        localChecking = false;
        noComputeGetUrl = false;
        noComputeToString = false;
      };
      extraOptions = {
        timeoutSecs = 0;
      };
      queryToCheck = {
        libraryPath = libraryPath;
        dbschemePath = dbScheme;
        queryPath = queryPath;
      };
      resultPath = qloPath;
      target = config.quick_eval and {
        quickEval = {
          quickEvalPos = {
            fileName = queryPath;
            line = config.startLine;
            column = config.startColumn;
            endLine = config.endLine;
            endColumn = config.endColumn;
          };
        };
      } or {
        query = {xx = ''}
      };
    };
    progressId = 1;
  }

  local runQueries_callback = function(err, result)
    if err then
      util.print_dump(err)
    else
      if vim.fn.glob(resultsPath) ~= '' then
        print("QLO: " .. qloPath)
        print("BQRS: " .. resultsPath)
        -- process results
        if config.quick_eval or config.metadata['kind'] ~= "path-problem" then
          local jsonPath = vim.fn.tempname() 
          local cmds = {
            {'codeql', 'bqrs', 'decode', '-o='..jsonPath, '--format=json', '--entities=string,url', resultsPath},
            {'load_json', jsonPath, dbPath, config.metadata}
          }
          job.runCommands(cmds)
          print("JSON: "..jsonPath)
        elseif config.metadata['kind'] == "path-problem" then
          local sarifPath = vim.fn.tempname() 
          local cmds = {
            {'codeql', 'bqrs', 'interpret', resultsPath, '-t=id='..config.metadata['id'], '-t=kind=path-problem', '-o='..sarifPath, '--format=sarif-latest'},
            {'load_sarif', sarifPath, dbPath, config.metadata}
          }
          job.runCommands(cmds)
          print("SARIF: "..sarifPath)
        end
      else
        print("BQRS files was not created")
        return
      end
    end
  end

  local compileQuery_callback = function(err, result)
    if err then
      util.print_dump(err)
    else
      -- prepare `runQueries` params
      local params = {
        body = {
          db = {
            dbDir = dbDir;
            workingSet = "default";
          };
          evaluateId = 0;
          queries = {
            {
              resultsPath = resultsPath;
              qlo = "file://"..qloPath;
              allowUnknownTemplates = true;
              id = 0;
              timeoutSecs = 0;
            }
          };
          stopOnError = false;
          useSequenceHint = false;
        };
        progressId = 2;
      }

      -- run query
      client.request("evaluation/runQueries", params, runQueries_callback)
    end
  end

  -- compile query
  client.request("compilation/compileQuery", params, compileQuery_callback)

end

function M.shutdown_server(buf)
  if clients[buf] then
    local client = clients[buf]
    local handle = client.handle
    util.print_dump(handle)
    handle:kill()
    clients[buf] = nil
  end
end

return M
-- vim:sw=2 ts=2 et
