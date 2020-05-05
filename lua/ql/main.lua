local util = require 'ql.util'
local queryserver = require 'ql.queryserver'
local vim = vim
local api = vim.api

database = ''

-- local functions

local function extract_query_metadata(query)
    local json = util.run_cmd('codeql resolve metadata --format=json '..query, true)
    local metadata, err = util.json_decode(json)
    if not metadata then
        print("Error resolving query metadata: "..err)
        return nil
    else
        return metadata
    end
end

-- exported functions

local M = {}

function M.set_database(_database)
    database = vim.fn.fnamemodify(_database, ':p')
    if not util.is_dir(database) then
        print('Incorrect database')
        return nil
    else
        print('Database set to '..database)
    end
end

function M.run_query(quick_eval)
    if database == '' then
        print('Missing database. Use SetDatabase command')
        return nil
    end

    if not util.is_dir(database..'/src') and util.is_file(database..'/src.zip') then
        util.run_cmd('mkdir '..database..'/src')
        util.run_cmd('unzip '..database..'/src.zip -d '..database..'/src')
    end

    local queryPath = vim.fn.expand('%:p')

	-- [bufnum, lnum, col, off, curswant]
    local line_start, column_start, line_end, column_end
    if vim.fn.mode() == "v" or vim.fn.mode() == "V" or vim.fn.mode() == "\\<C-V>" then
        line_start = vim.fn.getpos("'<")[2]
        column_start = vim.fn.getpos("'<")[3]
        line_end = vim.fn.getpos("'>")[2]
        column_end = vim.fn.getpos("'>")[3]
        column_end = column_end == 2147483647 and vim.fn.len(vim.fn.getline(line_end)) or column_end
    else
        line_start = vim.fn.getcurpos()[2]
        column_start = vim.fn.getcurpos()[3]
        line_end = vim.fn.getcurpos()[2]
        column_end = vim.fn.getcurpos()[3]
    end

    -- print("Quickeval at: "..line_start.."::"..column_start.."::"..line_end.."::"..column_end)

    local config = {
        quick_eval = quick_eval;
        buf = api.nvim_get_current_buf();
        query = queryPath;
        db = database;
        startLine = line_start;
        startColumn = column_start;
        endLine = line_end;
        endColumn = column_end;
        metadata = extract_query_metadata(queryPath);
        }

    queryserver.run_query(config)
end

return M
