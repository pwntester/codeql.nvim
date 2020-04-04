local util = require 'ql.util'
local vim = vim

local M = {}

function M.loadSarifResults(path)
    print(path)
    local f = io.open(path, "r")
    local body = f:read("*all")
    f:close()
    local decoded, err = util.json_decode(body)
    if not decoded then
        print("Error!! "..err)
        return
    end
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
                    node.filename = vim.fn["codeql#uriToFname"](l.location.physicalLocation.artifactLocation.uri)
                    node.line = l.location.physicalLocation.region.startLine
                    node.visitable = true
                    node.orig = {
                        label = l.location.message.text;
                        url = {
                            uri = l.location.physicalLocation.artifactLocation.uri;
                            startLine   = l.location.physicalLocation.region.startLine;
                            startColumn = l.location.physicalLocation.region.startColumn;
                            endColumn   = l.location.physicalLocation.region.endColumn;
                        };
                    }
                    table.insert(nodes, node)
                end
                local source = nodes[1]
                local sink = nodes[#nodes]
                local source_key = source.filename..'::'..source.orig.url.startLine..'::'..source.orig.url.startColumn..'::'..source.orig.url.endColumn
                local sink_key = sink.filename..'::'..sink.orig.url.startLine..'::'..sink.orig.url.startColumn..'::'..sink.orig.url.endColumn
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
--M.loadSarifResults("/Users/pwntester/Research/projects/ssti/freemarker/ofbiz/foo.sarif")

