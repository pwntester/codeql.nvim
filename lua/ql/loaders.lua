local util = require 'ql.util'
local vim = vim


local M = {}

function M.uriToFname(uri, database)
    colon = string.find(uri, ':')
    if colon == nil then return uri end
    scheme = string.sub(uri, 1, colon)
    path = string.sub(uri, colon+1)

    if string.sub(uri, colon+1, colon+2) ~= '//' then
        orig_fname = vim.uri_to_fname(scheme..'//'..path)
    else
        orig_fname = vim.uri_to_fname(uri)
    end
    if util.isFile(orig_fname) then
        return orig_fname
    elseif util.isDir(database..'/src') then
        return database..'/src'..orig_fname
    end
end

function M.loadJsonResults(path, database)
    if not util.isFile(path) then return end
    results = util.readJsonFile(path)
    if nil == results['#select'] then
        print('No results')
    end

    local issues = {}
    local tuples = results['#select']['tuples']

    for _, tuple in ipairs(tuples) do
        path = {}
        for _, element in ipairs(tuple) do
            local node = {}
            -- objects with url info
            if type(element) == "table" and nil ~= element['url'] then
                local filename = M.uriToFname(element['url']['uri'], database)
                local line = element['url']['startLine']
                node = {
                    label = element['label'];
                    mark = '→',
                    filename = filename;
                    line =  line,
                    visitable = (filename ~= nil and filename ~= '' and util.isFile(filename)) and true or false;
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
            elseif type(element) == "string" then
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
                node = {
                    label = element["label"];
                    mark = '≔';
                    filename = nil;
                    line = nil;
                    visitable = false;
                    url = element.url;
                }
            end
            table.insert(path, node)
        end

        -- add issue paths to issues list
        local paths = { path } 
        table.insert(issues, {
            is_folded = true;
            paths = paths;
            active_path = 0;
        })
    end

    return issues
end

function M.loadSarifResults(path, database)
    if not util.isFile(path) then return end
    local decoded = util.readJsonFile(path)
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
                    node.filename = M.uriToFname(l.location.physicalLocation.artifactLocation.uri, database)
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

    local issues = {}
    for _, p in pairs(paths) do
        local issue = {
            is_folded = true;
            paths = p;
            active_path = 0;
        }
        table.insert(issues, issue)
    end 

    return issues

end
return M
