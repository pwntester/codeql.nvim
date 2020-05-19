local util = require 'ql.util'
local loader = require 'ql.loader'
local rpc = require 'vim.lsp.rpc'
local protocol = require 'vim.lsp.protocol'
local vim = vim

local client_index = 0
local evaluate_id = 0
local progress_id = 0

-- local functions

local function next_client_id()
  client_index = client_index + 1
  return client_index
end

local function next_progress_id()
  progress_id = progress_id + 1
  return progress_id
end

local function next_evaluate_id()
  evaluate_id = evaluate_id + 1
  return evaluate_id
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
  local log_prefix = string.format("QueryServer[%s]", name)
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
    util.err_message(log_prefix, ': Error ', rpc.client_errors[code], ': ', vim.inspect(err))
    if config.on_error then
      local status, usererr = pcall(config.on_error, code, err)
      if not status then
        util.err_message(log_prefix, ' user on_error failed: ', tostring(usererr))
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

local last_message = ''

function M.start_server(buf)
  if get_query_client(buf) then
    return get_query_client(buf)
  end
  local ram_opts = util.resolve_ram(true)
  local cmd = {"codeql", "execute", "query-server", "--logdir", "/tmp/codeql"}
  vim.list_extend(cmd, ram_opts)
  local config = {
      cmd = cmd;
      offset_encoding = {"utf-8", "utf-16"};
      callbacks = {
        ['ql/progressUpdated'] = function(_, params, _)
            local message = params.message
            if message ~= last_message and nil == string.match(message, '^Stage%s%d.*%d%s%-%s*$') then
                util.message(message)
            end
            last_message = message
        end;
        ['evaluation/queryCompleted'] = function(_, result, _)
          util.message("Evaluation time: "..result.evaluationTime)
          if result.resultType == 0 then
            return {}
          elseif result.resultType == 1 then
            util.err_message(result.message or "ERROR: Other")
            return nil
          elseif result.resultType == 2 then
            util.err_message(result.message or "ERROR: OOM")
            return nil
          elseif result.resultType == 3 then
            util.err_message(result.message or "ERROR: Timeout")
            return nil
          elseif result.resultType == 4 then
            util.err_message(result.message or "ERROR: Query was cancelled")
            return nil
          end
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

  -- if config.quick_eval then
  --   util.message("Quickeval at: "..config.startLine.."::"..config.startColumn.."::"..config.endLine.."::"..config.endColumn)
  -- end

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
    progressId = next_progress_id();
  }

  local runQueries_callback = function(err, result)
    if err then
      util.err_message("ERROR: runQuery failed")
    end

    if util.is_file(bqrsPath) then
        loader.process_results(bqrsPath, dbPath, queryPath, config.metadata['kind'], config.metadata['id'], true)
    else
        util.err_message("ERROR: BQRS file cannot be found")
    end
  end

  local compileQuery_callback = function(_, result)
    local failed = false
    if not result then return end
    for _,msg in ipairs(result.messages) do
        if msg.severity == 0 then
            util.err_message(msg.message)
            failed = true
        end
    end
    if failed then
        return
    else
      -- prepare `runQueries` params
      local runQueries_params = {
        body = {
          db = {
            dbDir = dbDir;
            workingSet = "default";
          };
          evaluateId = next_evaluate_id();
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
        progressId = next_progress_id();
      }

      -- run query
      util.message("Running query")
      client.request("evaluation/runQueries", runQueries_params, runQueries_callback)
    end
  end

  -- compile query
  util.message("Compiling query")
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
