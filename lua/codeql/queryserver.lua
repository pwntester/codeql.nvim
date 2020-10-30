local util = require'codeql.util'
local loader = require'codeql.loader'
local rpc = require'vim.lsp.rpc'
local protocol = require'vim.lsp.protocol'
local vim = vim

local client_index = 0
local evaluate_id = 0
local progress_id = 0

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

local M = {}

M.client = nil

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
  local client = rpc.start(cmd, cmd_args, handlers, {
    cwd = config.cmd_cwd;
    env = config.cmd_env;
  })
  client.id = client_id
  return client
end


function M.start_server()

  if M.client then return M.client end

  util.message("Starting CodeQL Query Server")
  local cmd = {"codeql", "execute", "query-server", "--logdir", "/tmp/codeql"}
  vim.list_extend(cmd, util.resolve_ram(true))

  local last_message = ''

  local config = {
    cmd = cmd;
    offset_encoding = {"utf-8", "utf-16"};
    callbacks = {

      -- progress update
      ['ql/progressUpdated'] = function(_, params, _)
        local message = params.message
        if message ~= last_message and nil == string.match(message, '^Stage%s%d.*%d%s%-%s*$') then
          util.message(message)
        end
        last_message = message
      end;

      -- query completed
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
  return M.start_client(config)
end

function M.run_query(opts)

  if not M.client then M.client = M.start_server() end

  local queryPath = opts.query
  local qloPath = vim.fn.tempname()..'.qlo'
  local bqrsPath = vim.fn.tempname()..'.bqrs'
  local libraryPath = opts.libraryPath
  local dbschemePath = opts.dbschemePath
  local dbPath = opts.dbPath
  if not vim.endswith(dbPath, '/') then dbPath = dbPath .. '/' end

  local dbDir
  for _, dir in ipairs(vim.fn.glob(vim.fn.fnameescape(dbPath)..'*', 1, 1)) do
    if vim.startswith(dir, dbPath..'db-') then
      dbDir = dir
      break
    end
  end
  if not dbDir then
    util.err_message('Cannot find db')
    return
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
        dbschemePath = dbschemePath;
        queryPath = queryPath;
      };
      resultPath = qloPath;
      target = opts.quick_eval and {
        quickEval = {
          quickEvalPos = {
            fileName = queryPath;
            line = opts.startLine;
            column = opts.startColumn;
            endLine = opts.endLine;
            endColumn = opts.endColumn;
          };
        };
      } or {
        query = {xx = ''}
      };
    };
    progressId = next_progress_id();
  }

  local runQueries_callback = function(err, _)
    if err then
      util.err_message("ERROR: runQuery failed")
    end
    if util.is_file(bqrsPath) then
      loader.process_results(bqrsPath, dbPath, queryPath, opts.metadata['kind'], opts.metadata['id'], true)
    else
      util.err_message("ERROR: BQRS file cannot be found at "..bqrsPath)
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
              templateValues = opts.templateValues or nil;
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
      util.message(string.format("Running query [%s]", M.client.pid))
      M.client.request("evaluation/runQueries", runQueries_params, runQueries_callback)
    end
  end

  -- compile query
  util.message("Compiling query "..queryPath)

  M.client.request("compilation/compileQuery", compileQuery_params, compileQuery_callback)
end

function M.stop_server()
  if M.client then
    local handle = M.client.handle
    handle:kill()
    M.client = nil
  end
end

return M
