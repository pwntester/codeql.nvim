local util = require "codeql.util"
local config = require "codeql.config"

local M = {}

-- process a SARIF file and returns a table of issues
-- each issue is a table with the following fields:
---- is_folded: true if the issue is folded in the panel
---- paths: list of paths
---- active_path: active path index
---- hidden: true if the issue is hidden
---- node: primary node of the actie path
---- rule_id: the id of the rule generating the issue
-- each path is a list of nodes where each node is a table with the following fields:
---- label: label of the node
---- mark: mark (bullet)
---- filename: filename of the node
---- line: line number of the node
---- visitable: whether the node points to a visitable location
---- url: location of the node
-- the url is a table with the following fields:
---- uri: path of the file
---- startLine: line number of the node
---- startColumn: start column number of the node
---- endColumn: end column number of the node

function M.process_sarif(opts)
  if not util.is_file(opts.path) then
    return
  end
  config.sarif.path = opts.path
  local decoded = util.read_json_file(opts.path)
  if not decoded then
    return
  end

  -- TODO: handle multiple runs if thats even a thing
  local results = decoded.runs[1].results

  -- check if the SARIF file contains source code artifacts
  local artifacts = decoded.runs[1].artifacts
  if artifacts then
    for _, artifact in ipairs(artifacts) do
      if artifact.contents then
        config.sarif.hasArtifacts = true
        break
      end
    end
  end

  print("Sarif: " .. opts.path)
  print("Results: " .. #results)

  local issues = {}

  for i, r in ipairs(results) do
    local message = r.message.text
    local rule_id = r.ruleId

    if r.codeFlows == nil then
      -- results with NO codeFlows
      local nodes = {}
      local locations = {}
      --- location relevant to understanding the result.
      if r.relatedLocations then
        for _, v in ipairs(r.relatedLocations) do
          table.insert(locations, v)
        end
      end
      --- location where the result occurred
      if r.locations then
        for _, v in ipairs(r.locations) do
          table.insert(locations, v)
        end
      end
      for j, l in ipairs(locations) do
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
          uri = string.format("file:%s/%s", uriBaseId, uri)
        end
        local region = l.physicalLocation.region

        local node = {
          label = label,
          mark = mark,
          filename = util.uri_to_fname(uri) or uri,
          line = region and region.startLine or -1,
          visitable = region or false,
          url = {
            uri = uri,
            startLine = region and region.startLine or -1,
            startColumn = region and region.startColumn or -1,
            endColumn = region and region.endColumn or -1,
          },
        }

        -- check if the SARIF file contains source code snippets
        if l.physicalLocation.contextRegion and l.physicalLocation.contextRegion.snippet then
          config.sarif.hasSnippets = true
          node.contextRegion = l.physicalLocation.contextRegion
        end

        table.insert(nodes, node)
      end

      -- create issue
      local primary_node = nodes[#nodes]
      local issue = {
        is_folded = true,
        paths = { nodes },
        active_path = 1,
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
              uri = string.format("file:%s/%s", uriBaseId, uri)
            end
            local region = l.location.physicalLocation.region

            local node = {
              label = l.location.message.text,
              mark = mark,
              filename = util.uri_to_fname(uri) or uri,
              line = region and region.startLine or -1,
              visitable = region or false,
              url = {
                uri = uri,
                startLine = region and region.startLine or -1,
                startColumn = region and region.startColumn or -1,
                endColumn = region and region.endColumn or -1,
              },
            }

            -- check if the SARIF file contains source code snippets
            if l.location.physicalLocation.contextRegion and l.location.physicalLocation.contextRegion.snippet then
              config.sarif.hasSnippets = true
              node.contextRegion = l.location.physicalLocation.contextRegion
            end

            table.insert(nodes, node)
          end

          -- group code flows with same source and sink
          -- into a single issue with different paths
          if not opts.max_length or opts.max_length == -1 or #nodes <= opts.max_length then
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
              label = string.gsub(string.gsub(r.message.text, "\n", " "), "\\", ""),
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
        local primary_node
        if opts.group_by == "sink" then
          -- last node is the message node, so sink is #nodes - 1
          primary_node = p[1][#p[1] - 1]
        elseif opts.panel.group_by == "source" then
          -- first node is the message node, so source is 1
          primary_node = p[1][1]
        else
          -- default to source
          primary_node = p[1][1]
        end
        local issue = {
          is_folded = true,
          paths = p,
          active_path = 1,
          hidden = false,
          node = primary_node,
          rule_id = rule_id,
        }
        table.insert(issues, issue)
      end
    end
  end
  return issues
end

return M
