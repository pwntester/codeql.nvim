local util = require'codeql.util'
local panel = require'codeql.panel'
local vim = vim
local api = vim.api

-- local functions
local function generate_issue_label(node)
  local label = node.label

  if vim.g.codeql_panel_filename and node['filename'] and node['filename'] ~= nil then
    if vim.g.codeql_panel_longnames then
      label = node.filename..':'..node.line
    else
      label = vim.fn.fnamemodify(node.filename, ':p:t')..':'..node.line
    end
  end
  return label
end

local function uri_to_fname(uri, database)
  local colon = string.find(uri, ':')
  if colon == nil then return uri end
  local scheme = string.sub(uri, 1, colon)
  local path = string.sub(uri, colon+1)

  local orig_fname
  if string.sub(uri, colon+1, colon+2) ~= '//' then
    orig_fname = vim.uri_to_fname(scheme..'//'..path)
  else
    orig_fname = vim.uri_to_fname(uri)
  end
  if util.is_file(orig_fname) then
    return orig_fname
  elseif util.is_dir(database..'/src') then
    return database..'/src'..orig_fname
  end
end

-- exported functions
local M = {}

function M.process_results(bqrsPath, dbPath, queryPath, kind, id, save_bqrs)
  util.message("Processing results: " .. bqrsPath)
  util.message("dbPath: " .. dbPath)

  local info = util.bqrs_info(bqrsPath)
  local query_kinds = info['compatible-query-kinds']
  -- util.message(query_kinds)

  local count = info['result-sets'][1]['rows']
  local graph_properties = false
  for _, resultset in ipairs(info['result-sets']) do
    if resultset.name == "#select" then
      count = resultset.rows
    elseif resultset.name == "graphProperties" then
      graph_properties = true
    end
  end
  util.message(count.." rows found")

  local ram_opts = util.resolve_ram(true)

  -- process results
  if vim.tbl_contains(query_kinds, 'Graph') and
    vim.tbl_contains(query_kinds, 'Table') and
    graph_properties then
    local jsonPath = vim.fn.tempname()
    local cmd = {'codeql', 'bqrs', 'decode', '-o='..jsonPath, '--format=json', '--entities=id,url,string', bqrsPath}
    vim.list_extend(cmd, ram_opts)
    local cmds = { cmd, {'load_ast', jsonPath, dbPath} }
    util.message('Decoding BQRS ...')
    require'codeql.job'.run_commands(cmds)
    -- save BQRS if not called by :history
    if save_bqrs then
      require'codeql.history'.save_bqrs(bqrsPath, queryPath, dbPath, kind, id, count)
    end
  elseif vim.tbl_contains(query_kinds, 'PathProblem') and
    kind == 'path-problem' and
    id ~= nil then
    local sarifPath = vim.fn.tempname()
    local cmd = {'codeql', 'bqrs', 'interpret', bqrsPath, '-t=id='..id, '-t=kind='..kind, '-o='..sarifPath, '--format=sarif-latest'}
    vim.list_extend(cmd, ram_opts)
    local cmds = { cmd, {'load_sarif', sarifPath, dbPath} }
    util.message('Decoding BQRS ...')
    require'codeql.job'.run_commands(cmds)
    -- save BQRS if not called by :history
    if save_bqrs then
      require'codeql.history'.save_bqrs(bqrsPath, queryPath, dbPath, kind, id, count)
    end
  elseif vim.tbl_contains(query_kinds, 'PathProblem') and
    kind == 'path-problem' and
    id == nil then
    util.err_message("ERROR: Insuficient Metadata for a Path Problem. Need at least @kind and @id elements")
  else
    local jsonPath = vim.fn.tempname()
    local cmd = {'codeql', 'bqrs', 'decode', '-o='..jsonPath, '--format=json', '--entities=string,url', bqrsPath}
    vim.list_extend(cmd, ram_opts)
    local cmds = { cmd, {'load_raw', jsonPath, dbPath} }
    util.message('Decoding BQRS ...')
    require'codeql.job'.run_commands(cmds)
    -- save BQRS if not called by :history
    if save_bqrs then
      require'codeql.history'.save_bqrs(bqrsPath, queryPath, dbPath, kind, id, count)
    end
  end
  api.nvim_command('redraw')
end

function M.load_raw_results(path, database)
  if not util.is_file(path) then return end
  local results = util.read_json_file(path)
  if nil == results['#select'] then
    util.err_message('ERROR: No #select results')
  end

  local issues = {}
  local tuples = results['#select']['tuples']

  for _, tuple in ipairs(tuples) do
    path = {}
    for _, element in ipairs(tuple) do
      local node = {}
      -- objects with url info
      if type(element) == "table" and nil ~= element['url'] then
        local filename = uri_to_fname(element['url']['uri'], database)
        local line = element['url']['startLine']
        node = {
          label = element['label'];
          mark = '→',
          filename = filename;
          line =  line,
          visitable = (filename ~= nil and filename ~= '' and util.is_file(filename)) and true or false;
          url = element.url;
        }

        -- objects with no url info
      elseif type(element) == "table" and nil == element['url'] then
        node = {
          label = element['label'];
          mark = '≔';
          filename = nil;
          line = nil;
          visitable = false;
          url = element.url;
        }

        -- string literal
      elseif type(element) == "string" or type(element) == "number" then
        node = {
          label = element;
          mark = '≔';
          filename = nil;
          line = nil;
          visitable = false;
          url = nil;
        }

        -- ???
      else
        util.err_message("ERROR: Error processing node")
      end
      table.insert(path, node)
    end

    -- add issue paths to issues list
    local paths = { path }

    -- issue label
    local label = generate_issue_label(paths[1][1])

    table.insert(issues, {
      is_folded = true;
      paths = paths;
      active_path = 1;
      label = label;
      hidden = false;
      node = paths[1][1];
    })
  end

  panel.render(database, issues)
  api.nvim_command('redraw')
end

function M.load_sarif_results(path, database, max_length)
  if not util.is_file(path) then return end
  local decoded = util.read_json_file(path)
  local results = decoded.runs[1].results

  local paths = {}

  for _, r in ipairs(results) do
    -- each result contains a codeflow that groups a source
    for _, c in ipairs(r.codeFlows) do
      for _, t in ipairs(c.threadFlows) do
        -- each threadFlow contains all reached sinks for
        -- codeFlow source
        -- we can treat a threadFlow as a "regular" dataflow
        -- first element is source, last one is sink
        local nodes = {}
        for i, l in ipairs(t.locations) do
          local node = {}
          node.label = l.location.message.text
          if 1 == i then
            node.mark = '⭃'
          elseif #t.locations == i then
            node.mark = '⦿'
          else
            node.mark = '→'
          end
          node.filename = uri_to_fname(l.location.physicalLocation.artifactLocation.uri, database)
          node.line = l.location.physicalLocation.region.startLine
          node.visitable = true
          node.url = {
            uri = l.location.physicalLocation.artifactLocation.uri;
            startLine   = l.location.physicalLocation.region.startLine;
            startColumn = l.location.physicalLocation.region.startColumn;
            endColumn   = l.location.physicalLocation.region.endColumn;
          }
          table.insert(nodes, node)
        end

        if not max_length or max_length == -1 or #nodes <= max_length then
          local source = nodes[1]
          local sink = nodes[#nodes]
          local source_key = source.filename..'::'..source.url.startLine..'::'..source.url.startColumn..'::'..source.url.endColumn
          local sink_key = sink.filename..'::'..sink.url.startLine..'::'..sink.url.startColumn..'::'..sink.url.endColumn
          local key = source_key..'::'..sink_key

          if nil == paths[key] then
            paths[key] = {}
          end
          local l = paths[key]
          table.insert(l, nodes)
          paths[key] = l
        end
      end
    end
  end

  local issues = {}
  for _, p in pairs(paths) do

    -- issue label
    local primary_node = p[1][1]
    if vim.g.codeql_group_by_sink then
      primary_node = p[1][#(p[1])]
    end
    local label = generate_issue_label(primary_node)

    local issue = {
      is_folded = true;
      paths = p;
      active_path = 1;
      label = label;
      hidden = false;
      node = primary_node;
    }
    table.insert(issues, issue)
  end

  panel.render(database, issues)

  api.nvim_command('redraw')
end

return M
