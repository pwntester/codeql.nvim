local util = require "codeql.util"
local panel = require "codeql.panel"
local cli = require "codeql.cliserver"
local vim = vim
local api = vim.api
local format = string.format

local function generate_issue_label(node)
  local label = node.label

  if vim.g.codeql_panel_filename and node["filename"] and node["filename"] ~= nil then
    if vim.g.codeql_panel_longnames then
      label = node.filename
    elseif #vim.fn.fnamemodify(node.filename, ":p:t") > 0 then
      label = vim.fn.fnamemodify(node.filename, ":p:t")
    else
      label = node.label
    end
    if node.line and node.line > 0 then
      label = label .. ":" .. node.line
    end
  end

  return label
end

local M = {}

function M.uri_to_fname(uri)
  local colon = string.find(uri, ":")
  if colon == nil then
    return uri
  end
  local scheme = string.sub(uri, 1, colon)
  local path = string.sub(uri, colon + 1)

  if string.find(string.upper(path), "%%SRCROOT%%") then
    if vim.g.codeql_database then
      local sourceLocationPrefix = vim.g.codeql_database.sourceLocationPrefix
      path = string.gsub(path, "%%SRCROOT%%", sourceLocationPrefix)
    else
      -- TODO: request path to user
    end
  end

  local orig_fname
  if string.sub(uri, colon + 1, colon + 2) ~= "//" then
    orig_fname = vim.uri_to_fname(scheme .. "//" .. path)
  else
    orig_fname = vim.uri_to_fname(uri)
  end
  return orig_fname
end

function M.process_results(opts)
  local bqrsPath = opts.bqrs_path
  local dbPath = opts.db_path
  local queryPath = opts.query_path
  local kind = opts.query_kind
  local id = opts.query_id
  local save_bqrs = opts.save_bqrs
  local bufnr = opts.bufnr
  local ram_opts = vim.g.codeql_ram_opts
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
  util.message(format("Processing %s results", queryPath))
  util.message(format("%d rows found", count))

  if count == 0 then
    vim.notify("No results", 1)
    return
  end

  -- process definitions
  if vim.endswith(queryPath, "/localDefinitions.ql") then
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
    util.message("Decoding BQRS " .. bqrsPath)
    cli.runAsync(
      cmd,
      vim.schedule_wrap(function(_)
        if util.is_file(resultsPath) then
          require("codeql.defs").process_defs(resultsPath, bufnr)
        else
          util.err_message("ERROR: Cant find results at " .. resultsPath)
          panel.render()
        end
      end)
    )

    -- process references
  elseif vim.endswith(queryPath, "/localReferences.ql") then
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
    util.message("Decoding BQRS " .. bqrsPath)
    cli.runAsync(
      cmd,
      vim.schedule_wrap(function(_)
        if util.is_file(resultsPath) then
          require("codeql.defs").process_refs(resultsPath, bufnr)
        else
          util.err_message("ERROR: Cant find results at " .. resultsPath)
          panel.render()
        end
      end)
    )

    -- process printAST results
  elseif vim.endswith(queryPath, "/printAst.ql") then
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
    util.message("Decoding BQRS " .. bqrsPath)
    cli.runAsync(
      cmd,
      vim.schedule_wrap(function(_)
        if util.is_file(resultsPath) then
          require("codeql.ast").build_ast(resultsPath, bufnr)
        else
          util.err_message("ERROR: Cant find results at " .. resultsPath)
          panel.render()
        end
      end)
    )

    -- process SARIF results
  elseif vim.tbl_contains(query_kinds, "PathProblem") and kind == "path-problem" and id ~= nil then
    local cmd = {
      "bqrs",
      "interpret",
      "-v",
      "--log-to-stderr",
      "-t=id=" .. id,
      "-t=kind=" .. kind,
      "-o=" .. resultsPath,
      "--format=sarif-latest",
      bqrsPath,
    }
    vim.list_extend(cmd, ram_opts)
    util.message("Decoding BQRS " .. bqrsPath)
    cli.runAsync(
      cmd,
      vim.schedule_wrap(function(_)
        if util.is_file(resultsPath) then
          M.load_sarif_results(resultsPath)
        else
          util.err_message("ERROR: Cant find results at " .. resultsPath)
          panel.render()
        end
      end)
    )
    if save_bqrs then
      require("codeql.history").save_bqrs(bqrsPath, queryPath, dbPath, kind, id, count, bufnr)
    end
  elseif vim.tbl_contains(query_kinds, "PathProblem") and kind == "path-problem" and id == nil then
    util.err_message "ERROR: Insuficient Metadata for a Path Problem. Need at least @kind and @id elements"

    -- process RAW results
  else
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
    util.message("Decoding BQRS " .. bqrsPath)
    cli.runAsync(
      cmd,
      vim.schedule_wrap(function(_)
        if util.is_file(resultsPath) then
          M.load_raw_results(resultsPath)
        else
          util.err_message("ERROR: Cant find results at " .. resultsPath)
          panel.render()
        end
      end)
    )
    if save_bqrs then
      require("codeql.history").save_bqrs(bqrsPath, queryPath, dbPath, kind, id, count, bufnr)
    end
  end

  api.nvim_command "redraw"
end

--[[ DEBUG
  ["#select"] = {
    columns = { {
        kind = "Entity"
      }, {
        kind = "Entity",
        name = "t"
      }, {
        kind = "Entity",
        name = "s"
      } },
  ]]
--
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
    vim.notify("No results", 2)
    return
  end

  print("Json: " .. path)

  for _, tuple in ipairs(tuples) do
    path = {}
    for _, element in ipairs(tuple) do
      local node = {}
      -- objects with url info
      if type(element) == "table" and nil ~= element.url then
        local filename = M.uri_to_fname(element.url.uri)
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
      elseif type(element) == "table" and nil == element.url then
        node = {
          label = element.label,
          mark = "≔",
          filename = nil,
          line = nil,
          visitable = false,
          url = element.url,
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
        util.err_message "ERROR: Error processing node"
      end
      table.insert(path, node)
    end

    -- add issue paths to issues list
    local paths = { path }

    -- issue label
    local label = generate_issue_label(paths[1][1])

    table.insert(issues, {
      is_folded = true,
      paths = paths,
      active_path = 1,
      label = label,
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

  panel.render {
    issues = issues,
    kind = "raw",
    columns = col_names,
    mode = "table",
  }
  api.nvim_command "redraw"
end

function M.load_sarif_results(path)
  local max_length = vim.g.codeql_path_max_length
  if not util.is_file(path) then
    return
  end
  local decoded = util.read_json_file(path)
  local results = decoded.runs[1].results

  print("Sarif: " .. path)
  print("Results: " .. #results)

  local issues = {}

  for i, r in ipairs(results) do
    local message = r.message.text
    local rule_id = r.ruleId

    if r.codeFlows == nil then
      -- results with NO codeFlows
      local nodes = {}
      local locs = {}
      --- location relevant to understanding the result.
      if r.relatedLocations then
        locs = vim.list_extend(locs, r.relatedLocations)
      end
      --- location where the result occurred
      if r.locations then
        locs = vim.list_extend(locs, r.locations)
      end
      for j, l in ipairs(locs) do
        local label, mark
        if l.message then
          label = l.message.text or message
        else
          label = message
        end
        if #r.locations == j then
          mark = "⦿"
        else
          mark = "→"
        end
        local uri = l.physicalLocation.artifactLocation.uri
        local uriBaseId = l.physicalLocation.artifactLocation.uriBaseId
        if uriBaseId then
          uri = format("file:%s/%s", uriBaseId, uri)
        end
        local region = l.physicalLocation.region

        local node = {
          label = label,
          mark = mark,
          filename = M.uri_to_fname(uri) or uri,
          line = region and region.startLine or -1,
          visitable = region or false,
          url = {
            uri = uri,
            startLine = region and region.startLine or -1,
            startColumn = region and region.startColumn or -1,
            endColumn = region and region.endColumn or -1,
          },
        }
        table.insert(nodes, node)
      end

      -- create issue
      local primary_node = nodes[#nodes]
      local label = generate_issue_label(primary_node)
      local issue = {
        is_folded = true,
        paths = { nodes },
        active_path = 1,
        label = label,
        hidden = false,
        node = primary_node,
        rule_id = rule_id,
      }
      table.insert(issues, issue)
    else
      -- each result contains a codeflow that groups a source
      local paths = {}
      for _, c in ipairs(r.codeFlows) do
        for _, t in ipairs(c.threadFlows) do
          -- each threadFlow contains all reached sinks for
          -- codeFlow source
          -- we can treat a threadFlow as a "regular" dataflow
          -- first element is source, last one is sink
          local nodes = {}
          for j, l in ipairs(t.locations) do
            local mark
            if 1 == j then
              mark = "⭃"
            elseif #t.locations == i then
              mark = "⦿"
            else
              mark = "→"
            end
            local uri = l.location.physicalLocation.artifactLocation.uri
            local uriBaseId = l.location.physicalLocation.artifactLocation.uriBaseId
            if uriBaseId then
              uri = format("file:%s/%s", uriBaseId, uri)
            end
            local region = l.location.physicalLocation.region

            local node = {
              label = l.location.message.text,
              mark = mark,
              filename = M.uri_to_fname(uri) or uri,
              line = region and region.startLine or -1,
              visitable = region or false,
              url = {
                uri = uri,
                startLine = region and region.startLine or -1,
                startColumn = region and region.startColumn or -1,
                endColumn = region and region.endColumn or -1,
              },
            }

            table.insert(nodes, node)
          end

          -- group code flows with same source and sink
          -- into a single issue with different paths
          if not max_length or max_length == -1 or #nodes <= max_length then
            local source = nodes[1]
            local sink = nodes[#nodes]
            local source_key = source.filename
              .. "::"
              .. source.url.startLine
              .. "::"
              .. source.url.startColumn
              .. "::"
              .. source.url.endColumn
            local sink_key = sink.filename
              .. "::"
              .. sink.url.startLine
              .. "::"
              .. sink.url.startColumn
              .. "::"
              .. sink.url.endColumn
            local key = source_key .. "::" .. sink_key

            if not paths[key] then
              paths[key] = {}
            end
            local _path = paths[key]
            local message_node = {
              label = string.gsub(r.message.text, "\n", " "),
              mark = "≔",
              filename = nil,
              line = nil,
              visitable = false,
              url = nil,
            }
            table.insert(nodes, message_node)
            table.insert(_path, nodes)
            paths[key] = _path
          end
        end
      end

      -- create issue
      --- issue label
      for _, p in pairs(paths) do
        local primary_node = p[1][1]
        if vim.g.codeql_group_by_sink then
          -- last node is the message node, so sink is #nodes - 1
          primary_node = p[1][#p[1] - 1]
        end
        local label = generate_issue_label(primary_node)

        local issue = {
          is_folded = true,
          paths = p,
          active_path = 1,
          label = label,
          hidden = false,
          node = primary_node,
          rule_id = rule_id,
        }
        table.insert(issues, issue)
      end
    end
  end

  panel.render {
    issues = issues,
    kind = "sarif",
    mode = "tree",
  }
  api.nvim_command "redraw"
end

return M
