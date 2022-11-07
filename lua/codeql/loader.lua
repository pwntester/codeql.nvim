local util = require "codeql.util"
local panel = require "codeql.panel"
local cli = require "codeql.cliserver"
local config = require "codeql.config"
local sarif = require "codeql.sarif"

local M = {}

function M.process_results(opts)
  local conf = config.get_config()
  local bqrsPath = opts.bqrs_path
  local dbPath = opts.db_path
  local queryPath = opts.query_path
  local kind = opts.query_kind
  local id = opts.query_id
  local save_bqrs = opts.save_bqrs
  local bufnr = opts.bufnr
  local ram_opts = config.ram_opts
  local resultsPath = vim.fn.tempname()

  local info = util.bqrs_info(bqrsPath)
  if not info or info == vim.NIL or not info["result-sets"] then
    return
  end

  local query_kinds = info["compatible-query-kinds"]

  local count = info["result-sets"][1]["rows"]
  for _, resultset in ipairs(info["result-sets"]) do
    if resultset.name == "#select" then
      count = resultset.rows
    end
  end
  util.message(string.format("Processing %s results", queryPath))
  util.message(string.format("%d rows found", count))

  if count > 1000 then
    local continue = vim.fn.input(string.format("Too many results (%d). Open it? (Y/N): ", count))
    if string.lower(continue) ~= "y" then
      return
    end
  end

  if count == 0 then
    panel.render()
    return
  end

  -- process ASTs, definitions and references
  if vim.endswith(queryPath, "/localDefinitions.ql")
      or vim.endswith(queryPath, "/localReferences.ql")
      or vim.endswith(queryPath, "/printAst.ql")
  then
    local cmd = {
      "bqrs",
      "decode",
      "-v",
      "--log-to-stderr",
      "--format=json",
      "-o=" .. resultsPath,
      "--entities=id,url,string",
      bqrsPath,
    }
    vim.list_extend(cmd, ram_opts)
    cli.runAsync(
      cmd,
      vim.schedule_wrap(function(_)
        if util.is_file(resultsPath) then
          if vim.endswith(string.lower(queryPath), "/localdefinitions.ql") then
            require("codeql.defs").process_defs(resultsPath)
          elseif vim.endswith(string.lower(queryPath), "/localreferences.ql") then
            require("codeql.defs").process_refs(resultsPath)
          elseif vim.endswith(string.lower(queryPath), "/printast.ql") then
            require("codeql.ast").build_ast(resultsPath, bufnr)
          end
        else
          util.err_message("Cant find results at " .. resultsPath)
          panel.render()
        end
      end)
    )
    return
  end

  -- process SARIF results
  if vim.tbl_contains(query_kinds, "PathProblem") and kind == "path-problem" and id ~= nil then
    local cmd = {
      "bqrs",
      "interpret",
      "-v",
      "--log-to-stderr",
      "-t=id=" .. id,
      "-t=kind=" .. kind,
      "-o=" .. resultsPath,
      "--format=sarif-latest",
      "--max-paths=" .. conf.results.max_paths,
      bqrsPath,
    }
    vim.list_extend(cmd, ram_opts)
    cli.runAsync(
      cmd,
      vim.schedule_wrap(function(_)
        if util.is_file(resultsPath) then
          M.load_sarif_results(resultsPath)
        else
          util.err_message("Cant find results at " .. resultsPath)
          panel.render()
        end
      end)
    )
    if save_bqrs then
      require("codeql.history").save_bqrs(bqrsPath, queryPath, dbPath, kind, id, count, bufnr)
    end
    vim.api.nvim_command "redraw"
    return
  elseif vim.tbl_contains(query_kinds, "PathProblem") and kind == "path-problem" and id == nil then
    util.err_message "Insuficient Metadata for a Path Problem. Need at least @kind and @id elements"
    return
  end

  -- process RAW results
  local cmd = {
    "bqrs",
    "decode",
    "-v",
    "--log-to-stderr",
    "-o=" .. resultsPath,
    "--format=json",
    "--entities=string,url",
    bqrsPath,
  }
  vim.list_extend(cmd, ram_opts)
  cli.runAsync(
    cmd,
    vim.schedule_wrap(function(_)
      if util.is_file(resultsPath) then
        M.load_raw_results(resultsPath)
      else
        util.err_message("Cant find results at " .. resultsPath)
        panel.render()
      end
    end)
  )
  if save_bqrs then
    require("codeql.history").save_bqrs(bqrsPath, queryPath, dbPath, kind, id, count, bufnr)
  end
  vim.api.nvim_command "redraw"
end

function M.load_raw_results(path)
  if not util.is_file(path) then
    return
  end
  local results = util.read_json_file(path)
  local issues = {}
  local tuples, columns
  if results["#select"] then
    tuples = results["#select"].tuples
    columns = results["#select"].columns
  else
    for k, _ in pairs(results) do
      tuples = results[k].tuples
    end
  end

  if not tuples or vim.tbl_isempty(tuples) then
    panel.render()
    return
  end

  for _, tuple in ipairs(tuples) do
    path = {}
    for _, element in ipairs(tuple) do
      local node = {}
      -- objects with url info
      if type(element) == "table" and element.url then
        if element.url and element.url.endColumn then
          element.url.endColumn = element.url.endColumn + 1
        end
        local filename = util.uri_to_fname(element.url.uri)
        local line = element.url.startLine
        node = {
          label = element["label"],
          mark = "→",
          filename = filename,
          line = line,
          visitable = true,
          url = element.url,
        }

        -- objects with no url info
      elseif type(element) == "table" and not element.url then
        node = {
          label = element.label,
          mark = "≔",
          filename = nil,
          line = nil,
          visitable = false,
          url = nil,
        }

        -- string literal
      elseif type(element) == "string" or type(element) == "number" then
        node = {
          label = element,
          mark = "≔",
          filename = nil,
          line = nil,
          visitable = false,
          url = nil,
        }

        -- ???
      else
        util.err_message "Error processing node"
      end
      table.insert(path, node)
    end

    -- add issue paths to issues list
    local paths = { path }

    table.insert(issues, {
      is_folded = true,
      paths = paths,
      active_path = 1,
      hidden = false,
      node = paths[1][1],
      rule_id = "custom_query",
    })
  end

  local col_names = {}
  if columns then
    for _, col in ipairs(columns) do
      if col.name then
        table.insert(col_names, col.name)
      else
        table.insert(col_names, "---")
      end
    end
  else
    for _ = 1, #tuples[1] do
      table.insert(col_names, "---")
    end
  end

  panel.render(issues, {
    kind = "raw",
    columns = col_names,
    mode = "table",
  })
  vim.api.nvim_command "redraw"
end

function M.load_sarif_results(path)
  local conf = config.get_config()
  local issues = sarif.process_sarif {
    path = path,
    max_length = conf.results.max_path_depth,
    group_by = conf.panel.group_by,
  }
  panel.render(issues, {
    kind = "sarif",
    mode = "tree",
  })
  vim.api.nvim_command "redraw"
end

return M
