local util = require "codeql.util"
local panel = require "codeql.panel"
local cli = require "codeql.cliserver"
local config = require "codeql.config"
local sarif = require "codeql.sarif"
local vim = vim

local M = {}

function M.process_results(opts, info)
  local conf = config.config
  local bqrsPath = opts.bqrs_path
  local queryPath = opts.query_path
  local dbPath = opts.db_path
  local kind = opts.query_kind
  local id = opts.query_id
  local save_bqrs = opts.save_bqrs
  local bufnr = opts.bufnr
  local ram_opts = config.ram_opts
  local resultsPath = vim.fn.tempname()
  if not info or info == vim.NIL or not info["result-sets"] then
    return
  end

  local query_kinds = info["compatible-query-kinds"]

  local count, total_count = 0, 0
  local found_select_rs = false
  for _, resultset in ipairs(info["result-sets"]) do
    if resultset.name == "#select" then
      found_select_rs = true
      count = resultset.rows
      break
    else
      total_count = total_count + resultset.rows
    end
  end
  if not found_select_rs then
    count = total_count
  end

  if count == 0 then
    util.message(string.format("No results for %s", queryPath))
    panel.render()
    return
  else
    util.message(string.format("Processing %d results for %s", count, queryPath))
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
        if not util.is_file(resultsPath) then
          util.err_message("Error: Failed to decode results for " .. queryPath)
          return
        end
        if vim.endswith(string.lower(queryPath), "/localdefinitions.ql") then
          require("codeql.defs").process_defs(resultsPath)
        elseif vim.endswith(string.lower(queryPath), "/localreferences.ql") then
          require("codeql.defs").process_refs(resultsPath)
        elseif vim.endswith(string.lower(queryPath), "/printast.ql") then
          require("codeql.ast").build_ast(resultsPath, bufnr)
        end
      end)
    )
    return
  end

  if count > 1000 then
    local continue = vim.fn.input(string.format("Too many results (%d). Open it? (Y/N): ", count))
    if string.lower(continue) ~= "y" then
      return
    end
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
          util.err_message("Error: Cant find SARIF results at " .. resultsPath)
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
        util.err_message("Error: Cant find raw results at " .. resultsPath)
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
  if results then
    local issues = {}
    local col_names = {}
    for name, v in pairs(results) do
      local tuples = v.tuples
      local columns = v.columns

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
            util.err_message(string.format("Error processing node (%s)", type(element)))
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
          query_id = name,
        })
      end

      col_names[name] = {}
      if columns then
        for _, col in ipairs(columns) do
          if col.name then
            table.insert(col_names[name], col.name)
          else
            table.insert(col_names[name], "---")
          end
        end
      else
        for _ = 1, #tuples[1] do
          table.insert(col_names[name], "---")
        end
      end
    end

    if vim.tbl_isempty(issues) then
      panel.render()
      return
    else
      panel.render({
        source = "raw",
        mode = "table",
        issues = issues,
        columns = col_names,
      })
      vim.api.nvim_command "redraw"
    end
  end

end

function M.load_sarif_results(path)
  local conf = config.config
  local issues = sarif.process_sarif {
    path = path,
    max_length = conf.results.max_path_depth,
    group_by = conf.panel.group_by,
  }
  panel.render({
    source = "sarif",
    mode = "tree",
    issues = issues,
  })
  vim.api.nvim_command "redraw"
end

return M
