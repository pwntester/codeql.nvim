local util = require 'ql.util'
local loader = require 'ql.loader'
local panel = require 'ql.panel'

local M = {}

local commandlist = {}

function M.runCommands(commands)
    commandlist = commands
    M.runCommandsHandler()
end

function M.runCommandsHandler()

    if #commandlist > 0 then
        local cmd = commandlist[1]
        commandlist = util.slice(commandlist, 2, #commandlist)


        if cmd[1] == 'load_sarif' then
            --  ['load_sarif', sarifPath, database, metadata]
            if util.isFile(cmd[2]) then
                loader.loadSarifResults(cmd[2], cmd[3])
                M.runCommandsHandler()
            else
                print('Cant find SARIF results at '..cmd[2])
                panel.render(cmd[3], {})
            end
        elseif cmd[1] == 'load_json' then
            -- ['load_json', path, database, metadata]
            if util.isFile(cmd[2]) then
                loader.loadJsonResults(cmd[2], cmd[3])
                M.runCommandsHandler()
            else
                print('Cant find JSON results at '..cmd[2])
                panel.render(cmd[3], {})
            end
        else
            vim.loop.spawn(cmd[1], {
                args = util.slice(cmd, 2, #cmd)
            },
            vim.schedule_wrap(M.runCommandsHandler))
        end
    end
end

return M
