local util = require 'ql.util'
local loader = require 'ql.loader'
local panel = require 'ql.panel'

local commandlist = {}

-- local functions
local function run_commands_handler()

    if #commandlist > 0 then
        local cmd = commandlist[1]
        commandlist = util.tbl_slice(commandlist, 2, #commandlist)

        if cmd[1] == 'load_sarif' then
            --  ['load_sarif', sarifPath, database, metadata]
            if util.is_file(cmd[2]) then
                loader.load_sarif_results(cmd[2], cmd[3], vim.g.codeql_path_max_length)
                run_commands_handler()
            else
                util.err_message('ERROR: Cant find SARIF results at '..cmd[2])
                panel.render(cmd[3], {})
            end
        elseif cmd[1] == 'load_raw' then
            -- ['load_raw', path, database, metadata]
            if util.is_file(cmd[2]) then
                loader.load_raw_results(cmd[2], cmd[3])
                run_commands_handler()
            else
                util.err_message('ERROR: Cant find raw results at '..cmd[2])
                panel.render(cmd[3], {})
            end
        else
            vim.loop.spawn(cmd[1], {
                args = util.tbl_slice(cmd, 2, #cmd)
            },
            vim.schedule_wrap(run_commands_handler))
        end
    end
end

-- exported functions
local M = {}

function M.run_commands(commands)
    commandlist = commands
    run_commands_handler()
end

return M
