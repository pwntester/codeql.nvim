local util = require 'ql.util'
local vim = vim
local api = vim.api

local history = {}

-- exported functions

local M = {}

function M.save_bqrs(bqrs_path, query_path, db_path, kind, id, count)
    -- should we store quickEval results?
    local entry = {
        bqrs = bqrs_path;
        query = query_path;
        database = db_path;
        epoch = vim.fn.localtime();
        time = vim.fn.strftime('%c');
        kind = kind;
        id = id;
        count = count;
    }
    table.insert(history, entry)
end

function M.menu()
    api.nvim_command('redraw')
    local options = { 'Select:' }
    for i, entry in ipairs(history) do
        if util.is_file(entry.bqrs) then
            local entry_text = i..'. '..vim.fn.fnamemodify(entry.query, ':t')..' ('..entry.count..' results) ('..entry.time..') '..entry.database
            table.insert(options, entry_text)
        end
    end
    local choice = vim.fn.inputlist(options)
    if choice < 1 or choice > #history then
        return
    elseif choice < 1 + #history then
        local entry = history[choice]
        if entry then
            require'ql.loader'.process_results(entry.bqrs, entry.database, entry.query, entry.kind, entry.id, false)
        end
    end
end

return M
