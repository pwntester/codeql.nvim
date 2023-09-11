local util = require "codeql.util"
local loader = require "codeql.loader"
local config = require "codeql.config"
local rpc = require "vim.lsp.rpc"
local protocol = require "vim.lsp.protocol"

local client_index = 0
local progress_id = -1
local last_rpc_msg_id = -1
local lsp_client_id
local lsp_progress_handler
local progress_stage

local function next_client_id()
  client_index = client_index + 1
  return client_index
end

local function next_progress_id()
  progress_id = progress_id + 1
  return progress_id
end

local M = {}

M.client = nil

function M.start_client(opts)
  local cmd, cmd_args = util.cmd_parts(opts.cmd)

  local client_id = next_client_id()

  local callbacks = opts.callbacks or {}
  local name = opts.name or tostring(client_id)
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
    util.err_message(string.format("%s: Error %s: %s", log_prefix, rpc.client_errors[code], vim.inspect(err)))
    if opts.on_error then
      local status, usererr = pcall(opts.on_error, code, err)
      if not status then
        util.err_message(string.format("%s user on_error failed: ", log_prefix, tostring(usererr)))
      end
    end
  end

  function handlers.on_exit(code, signal)
    if opts.on_exit then
      pcall(opts.on_exit, code, signal)
    end
  end

  -- Start the RPC client.
  local client = rpc.start(cmd, cmd_args, handlers, {
    env = opts.cmd_env,
  })
  client.id = client_id
  return client
end

function M.get_lsp_client_id()
  if lsp_client_id then
    return lsp_client_id
  else
    local lsp_clients = vim.lsp.get_active_clients()
    for _, lsp_client in ipairs(lsp_clients) do
      if lsp_client.name == "codeqlls" then
        lsp_client_id = lsp_client.id
        return lsp_client_id
      end
    end
  end
end

function M.get_lsp_handler()
  if lsp_progress_handler then
    return lsp_progress_handler
  end
  lsp_progress_handler = vim.lsp.handlers["$/progress"]
  return lsp_progress_handler
end

function M.start_server()
  if M.client then
    return M.client
  end

  util.message "Starting CodeQL Query Server"
  local cmd = {
    "codeql",
    "execute",
    "query-server2",
    "--debug", "--tuple-counting", "--threads=0",
    "--evaluator-log-level", "5",
    "-v",
    "--log-to-stderr",
    --"--additional-packs", "/Users/pwntester/src/github.com/github/securitylab-codeql",
  }
  local conf = config.config
  vim.list_extend(cmd, conf.ram_opts)

  local opts = {
    cmd = cmd,
    offset_encoding = { "utf-8", "utf-16" },
    callbacks = {

      -- progress update
      ["ql/progressUpdated"] = function(_, params, _)
        local client_id = M.get_lsp_client_id()
        local lsp_handler = M.get_lsp_handler()
        local message = params.message
        local progress = (100 * params.step) / params.maxStep
        if progress == 0 and not progress_stage then
          progress_stage = "begin"
        elseif progress == 0 then
          return
        elseif params.step >= params.maxStep - 1 then
          progress_stage = "end"
        end

        local handler
        if client_id and lsp_handler and type(lsp_handler) == "function" then
          -- use LSP progress handler
          handler = function(result)
            -- https://github.com/neovim/neovim/blob/b8ad1bfe8bc23ed5ffbfe43df5fda3501f1d2802/runtime/lua/vim/lsp/handlers.lua#L24
            local ctx = {
              client_id = M.get_lsp_client_id()
            }
            --vim.lsp.handlers["$/progress"](nil, {value = { message = "foo"}, token = "foo"}, { client_id = vim.lsp.get_active_clients()[1].id })
            --print(vim.inspect(result), vim.inspect(ctx))
            lsp_handler(nil, result, ctx)
          end
        else
          -- Use vim.notify
          handler = function(result)
            if result.message then
              util.message("Query execution progress: " .. result.value.message)
            end
          end
        end

        if progress_stage == "begin" then
          handler({
            token = "CodeQLToken",
            value = {
              kind = progress_stage,
              title = "CodeQL",
              percentage = 0,
            },
          })
          progress_stage = "report"
        elseif progress_stage == "report" then
          handler({
            token = "CodeQLToken",
            value = {
              kind = progress_stage,
              message = message,
              percentage = progress,
            },
          })
        elseif progress_stage == "end" then
          handler({
            token = "CodeQLToken",
            value = {
              kind = progress_stage,
              percentage = 100,
            },
          })
          progress_stage = nil
        end
      end,
    }
  }
  return M.start_client(opts)
end

function M.run_query(opts)
  local dbPath = config.database.path
  if not dbPath then
    --util.err_message "Cannot find dataset folder. Did you :SetDatabase?"
    return
  end

  if not M.client then
    M.client = M.start_server()
  end

  local bufnr = opts.bufnr
  local queryPath = opts.query
  local bqrsPath = string.format(vim.fn.tempname(), ".bqrs")

  local additionalPacks = util.get_additional_packs()

  local runQuery_params = {
    body = {
      db = dbPath,
      additionalPacks = {
        additionalPacks or ""
      },
      externalInputs = {},
      singletonExternalInputs = opts.templateValues or {},
      outputPath = bqrsPath,
      queryPath = queryPath,
      -- do we want Datalog Intermediary Language dumps?
      -- https://codeql.github.com/docs/codeql-overview/codeql-glossary/#dil
      -- dilPath = "",
      -- logPath = "",
      target = opts.quick_eval and {
        quickEval = {
          quickEvalPos = {
            fileName = queryPath,
            line = opts.startLine,
            column = opts.startColumn,
            endLine = opts.endLine,
            endColumn = opts.endColumn,
          },
        },
      } or {
        query = { xx = "" },
      },
    },
    progressId = next_progress_id(),
  }

  local runQuery_callback = function(err, resp)
    if err then
      util.err_message("ERROR: " .. vim.inspect(err))
    end
    if not resp then
      -- we may have got an RPC error, so print it
      -- this is possible if the language server crashed, etc
      return
    end
    if resp["resultType"] == 0 then
      if util.is_file(bqrsPath) then
        util.bqrs_info({
          bqrs_path = bqrsPath,
          bufnr = bufnr,
          db_path = dbPath,
          query_path = queryPath,
          query_kind = opts.metadata["kind"],
          query_id = opts.metadata["id"],
          save_bqrs = true,
        }, loader.process_results)
      end
    elseif resp["resultType"] == 1 then
      util.err_message("ERROR: Other: " .. resp["message"])
    elseif resp["resultType"] == 2 then
      util.err_message("ERROR: Compilation Error: " .. resp["message"])
    elseif resp["resultType"] == 3 then
      util.err_message("ERROR: OOM Error: " .. resp["message"])
    elseif resp["resultType"] == 4 then
      util.err_message("ERROR: Query cancelled: " .. resp["message"])
    elseif resp["resultType"] == 5 then
      util.err_message("ERROR: DB Scheme mismatch: " .. resp["message"])
    elseif resp["resultType"] == 6 then
      util.err_message("ERROR: DB Scheme no upgrade found: " .. resp["message"])
    else
      util.err_message "Query run failed. Database may be locked by a different Query Server"
    end
  end

  -- run query
  util.message(string.format("Running query %s", queryPath))

  _, last_rpc_msg_id = M.client.request(
    "evaluation/runQuery",
    runQuery_params,
    runQuery_callback
  )
end

function M.register_database(database)
  if not M.client then
    M.client = M.start_server()
  end
  config.database = database
  local lang = config.database.languages[1]
  -- https://github.com/github/vscode-codeql/blob/e913165249a272e13a785f542fa50c6a9d4eeb38/extensions/ql-vscode/src/helpers.ts#L432-L440
  local langTodbScheme = {
    javascript = 'semmlecode.javascript.dbscheme',
    cpp = 'semmlecode.cpp.dbscheme',
    java = 'semmlecode.dbscheme',
    python = 'semmlecode.python.dbscheme',
    csharp = 'semmlecode.csharp.dbscheme',
    go = 'go.dbscheme',
    ruby = 'ruby.dbscheme',
    ql = 'ql.dbscheme'
  }
  local dbschemePath = config.database.datasetFolder .. "/" .. langTodbScheme[lang]
  if not vim.fn.filereadable(dbschemePath) then
    util.err_message("Cannot find dbscheme file")
    return
  else
    util.message(string.format("Using dbscheme file %s", dbschemePath))
  end
  local resp = util.database_upgrades(dbschemePath)
  if resp ~= vim.NIL and #resp.scripts > 0 then
    util.database_upgrade(config.database.path)
  end
  util.message(string.format("Registering database %s", config.database.path))
  local params = {
    body = {
      databases = {
        config.database.path
      },
      progressId = next_progress_id(),
    },
  }
  M.client.request("evaluation/registerDatabases", params, function(err, result)
    if err then
      util.err_message(string.format("Error registering database %s", vim.inspect(err)))
    else
      util.message(string.format("Successfully registered %s", result.registeredDatabases[1]))
      -- TODO: add option to open the drawer automatically
      --require 'codeql.explorer'.draw()
    end
  end)
end

function M.unregister_database(cb)
  if util.is_blank(config.database) then
    vim.notify("No database registered")
    return
  end
  if not M.client then
    M.client = M.start_server()
  end
  util.message(string.format("Deregistering database %s", config.database.path))
  local params = {
    body = {
      databases = {
        config.database.path,
      },
      progressId = next_progress_id(),
    },
  }
  M.client.request("evaluation/deregisterDatabases", params, function(err, result)
    if err then
      util.err_message(string.format("Error registering database %s", vim.inspect(err)))
    elseif #result.registeredDatabases == 0 then
      util.message(string.format("Successfully deregistered %s", config.database.path))
      config.database = nil
    end
    -- call the callback
    if cb then
      cb()
    end
  end)
end

function M.cancel_query()
  if last_rpc_msg_id < 0 then
    return
  end
  if not M.client then
    M.client = M.start_server()
  end
  util.message(M.client.notify("$/cancelRequest", {
    id = last_rpc_msg_id,
  }))
end

function M.stop_server()
  if M.client then
    local handle = M.client.handle
    handle:kill()
    M.client = nil
  end
end

return M
