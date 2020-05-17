local util = require 'ql.util'
local loader = require 'ql.loader'
local rpc = require 'vim.lsp.rpc'
local protocol = require 'vim.lsp.protocol'
local vim = vim
local api = vim.api

local client_index = 0

-- local functions
local function next_client_id()
  client_index = client_index + 1
  return client_index
end

local function err_message(...)
  api.nvim_err_writeln(table.concat(vim.tbl_flatten{...}))
  api.nvim_command("redraw")
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

local clients = {}

local function get_query_client(bufnr)
    if bufnr == 0 then bufnr = vim.fn.bufnr(0) end
    return clients[bufnr]
end

local function set_query_client(bufnr, client)
    if bufnr == 0 then bufnr = vim.fn.bufnr(0) end
    clients[bufnr] = client
end

-- exported functions
local M = {}

function M.start_client(config)
  local cmd, cmd_args = cmd_parts(config.cmd)

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

function M.start_server(buf)
  if get_query_client(buf) then
    --print("Query Server already started for buffer "..buf)
    return get_query_client(buf)
  end
  local ram_opts = util.resolve_ram(true)
  local cmd = {"codeql", "execute", "query-server", "--logdir", "/tmp/codeql"}
  vim.list_extend(cmd, ram_opts)
  local config = {
      cmd             = cmd;
      offset_encoding = {"utf-8", "utf-16"};
      callbacks = {
        ['ql/progressUpdated'] = function(_, params, _)
          print(params.message)
        end;
        ['evaluation/queryCompleted'] = function(_, _, _)
          -- TODO: if ok, return {}, else return error (eg rpc.rpc_response_error(protocol.ErrorCodes.MethodNotFound))
          return {}
        end
      }
  }
  local client = M.start_client(config)
  set_query_client(buf, client)
  return client
end

function M.run_query(config)

  -- TODO: store client as buffer var
  local client = get_query_client(0)
  if not client then
    client = M.start_server(config.buf)
    set_query_client(0, client)
    --print('New Query Server started with PID: '..client.pid)
  end
  local queryPath = config.query
  local dbPath = config.db
  local qloPath = vim.fn.tempname()..'.qlo'
  local bqrsPath = vim.fn.tempname()..'.bqrs'
  local libPaths = util.resolve_library_path(queryPath)
  local libraryPath = libPaths.libraryPath
  local dbScheme = libPaths.dbscheme
  local dbDir = dbPath

  for _, dir in ipairs(vim.fn.glob(vim.fn.fnameescape(dbPath)..'*', 1, 1)) do
    if vim.startswith(dir, dbPath..'db-') then
      dbDir = dir
      break
    end
  end

  -- https://github.com/github/vscode-codeql/blob/master/extensions/ql-vscode/src/messages.ts
  local compileQuery_params = {
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
      print("ERROR: runQuery failed")
      util.print_dump(err)
    end

    if util.is_file(bqrsPath) then
        loader.process_results(bqrsPath, dbPath, queryPath, config.metadata['kind'], config.metadata['id'], true)
    else
        print("ERROR: runQuery failed")
        util.print_dump(result)
    end
  end

  local compileQuery_callback = function(err, _)
    if err then
      print("ERROR: compileQuery failed")
      util.print_dump(err)
    else
      -- prepare `runQueries` params
      local runQueries_params = {
        body = {
          db = {
            dbDir = dbDir;
            workingSet = "default";
          };
          evaluateId = 0;
          queries = {
            {
              resultsPath = bqrsPath;
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
      print("Running query")
      client.request("evaluation/runQueries", runQueries_params, runQueries_callback)
    end
  end

  -- compile query
  print("Compiling query")
  client.request("compilation/compileQuery", compileQuery_params, compileQuery_callback)
end

function M.stop_server(buf)
  if not buf then
    buf = vim.fn.bufnr()
  end
  if get_query_client(buf) then
    local client = get_query_client(buf)
    local handle = client.handle
    handle:kill()
    set_query_client(buf, nil)
  end
end

return M
