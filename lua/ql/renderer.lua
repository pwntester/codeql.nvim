local util = require 'ql.util'
local vim = vim
local api = vim.api

local M = {}

local scaninfo = {}
local auditpanel_buffer_name = '__CodeQLPanel__'
local auditpanel_pos = 'right'
local auditpanel_width = 50
local auditpanel_short_help = true
local auditpanel_longnames = false
local auditpanel_filename = true
local auditpanel_iconchars = {'▶', '▼'}
local icon_closed = auditpanel_iconchars[1]
local icon_open = auditpanel_iconchars[2]

local issues = {}
local metadata = {}
local database = ''

function M.render(_database, _metadata, _issues)
    M.openAuditPanel()
    issues = _issues
    if string.sub(_database, -1) == "/" then
        database = string.sub(_database, 1, -2)
    else
        database = _database
    end
    metadata = _metadata
    scaninfo = { line_map =  {} }
    M.renderContent()
end

function M.renderContent()
    local bufnr = vim.fn.bufnr(auditpanel_buffer_name)
    if bufnr == -1 then print('Error opening CodeQL panel'); return end
    api.nvim_buf_set_option(bufnr, 'modifiable', true)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    M.printHelp()
    if next(issues) ~= nil then
        M.printIssues()
        local win = M.getPanelWindow(auditpanel_buffer_name)
        api.nvim_win_set_cursor(win, {6, 0})
    else
        M.printToPanel('No results found.')
    end
    api.nvim_buf_set_option(bufnr, 'modifiable', false)
end

function M.openAuditPanel()

    -- check if audit pane is already opened
    if vim.fn.bufwinnr(auditpanel_buffer_name) ~= -1 then
        return
    end

    -- prepare split arguments
    local pos = ''
    if auditpanel_pos == 'right' then
        pos = 'botright'
    elseif auditpanel_pos == 'left' then
        pos = 'topleft'
    else
        print('Incorrect auditpanel_pos value')
        return
    end

    -- get current win id
    local current_window = vim.fn.win_getid()

    -- go to main window
    M.goToMainWindow()

    -- split
    vim.fn.execute('silent keepalt '..pos..' vertical '..auditpanel_width..'split '..auditpanel_buffer_name)

    -- go to original window
    vim.fn.win_gotoid(current_window)

    -- buffer options
    local bufnr = vim.fn.bufnr(auditpanel_buffer_name)
    api.nvim_buf_set_option(bufnr, 'filetype', 'codeqlauditpanel')
    api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
    api.nvim_buf_set_option(bufnr, 'bufhidden', 'hide')
    api.nvim_buf_set_option(bufnr, 'swapfile', false)
    api.nvim_buf_set_option(bufnr, 'buflisted', false)

    api.nvim_buf_set_keymap(bufnr, 'n', 'o', '<Cmd>lua ToggleFold()<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', '<Cmd>lua JumpToCode(0)<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'p', '<Cmd>lua JumpToCode(1)<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'F', '<Cmd>lua ShowLongNames()<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'f', '<Cmd>lua ShowFilename()<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'H', '<Cmd>lua ToggleHelp()<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'q', '<Cmd>lua CloseAuditPanel()<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'O', '<Cmd>lua SetFoldLevel(false)<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'c', '<Cmd>lua SetFoldLevel(true)<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'P', '<Cmd>lua ChangePath(-1)<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'N', '<Cmd>lua ChangePath(1)<CR>', { script = true,  silent = true})

    -- window options
    local win = M.getPanelWindow(auditpanel_buffer_name)
    api.nvim_win_set_option(win, 'wrap', false)
    api.nvim_win_set_option(win, 'number', false)
    api.nvim_win_set_option(win, 'relativenumber', false)
    api.nvim_win_set_option(win, 'foldenable', false)
    api.nvim_win_set_option(win, 'winfixwidth', true)
    api.nvim_win_set_option(win, 'concealcursor', 'nvi')
    api.nvim_win_set_option(win, 'conceallevel', 3)
    api.nvim_win_set_option(win, 'signcolumn', 'yes')

end

function M.getPanelWindow(buffer_name)
    local bufnr = vim.fn.bufnr(buffer_name)
    for _, w in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_get_buf(w) == bufnr then
            return w
        end
    end
    return nil
end

function M.goToMainWindow()
    local widerwin = 0
    local widerwidth = 0
    for _, w in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_get_width(w) > widerwidth then
            widerwin = w
            widerwidth = api.nvim_win_get_width(w)
        end
    end
    if widerwin > -1 then
        vim.fn.win_gotoid(widerwin)
    end
end

function M.printToPanel(text, matches)
    local bufnr = vim.fn.bufnr(auditpanel_buffer_name)
    api.nvim_buf_set_lines(bufnr, -1, -1, true, {text})
    if type(matches) == 'table' then
        for hlgroup, groups in pairs(matches) do
            for _, group in ipairs(groups) do
                local linenr = api.nvim_buf_line_count(bufnr) - 1
                api.nvim_buf_add_highlight(bufnr, 0, hlgroup, linenr, group[1], group[2])
            end
        end
    end
end

function M.printHelp()
    if auditpanel_short_help then
        M.printToPanel('" Press H for help')
        M.printToPanel('')
    else
        M.printToPanel('" --------- General ---------')
        M.printToPanel('" <CR>: Jump to tag definition')
        M.printToPanel('" p: As above, but stay in AuditPane')
        M.printToPanel('" f: Show file names')
        M.printToPanel('" F: Show long file names')
        M.printToPanel('" P: Previous path')
        M.printToPanel('" N: Next path')
        M.printToPanel('"')
        M.printToPanel('" ---------- Folds ----------')
        M.printToPanel('" o: Toggle fold')
        M.printToPanel('" O: Open all folds')
        M.printToPanel('" c: Close all folds')
        M.printToPanel('"')
        M.printToPanel('" ---------- Misc -----------')
        M.printToPanel('" q: Close window')
        M.printToPanel('" s: Toggle help')
        M.printToPanel('')
    end
end

function M.renderKeepView(line)
    if line == nil then line = vim.fn.line('.') end

    -- called from ToggleFold commands, so within panel buffer
    local curcol = vim.fn.col('.')
    local topline = vim.fn.line('w0')

    M.renderContent()

    local scrolloff_save = api.nvim_get_option('scrolloff')
    api.nvim_command('set scrolloff=0')

    vim.fn.cursor(topline, 1)
    api.nvim_command('normal! zt')
    vim.fn.cursor(line, curcol)

    api.nvim_command('let &scrolloff = '..scrolloff_save)
    api.nvim_command('redraw')
end

function M.printIssues()

    local hl = { CodeqlAuditPanelInfo = {{0, string.len('Database:')}} }
    local index = string.find(database, '/[^/]*$')
    if nil ~= index then
        M.printToPanel('Database: '..string.sub(database, index + 1), hl)
    else
        M.printToPanel('Database: '..database, hl)
    end


    hl = { CodeqlAuditPanelInfo = {{0, string.len('Issues:')}} }
    M.printToPanel('Issues:   '..table.getn(issues), hl)

    M.printToPanel('')

    -- print issue labels
    for _, issue in ipairs(issues) do
        local paths = issue.paths
        local is_folded = issue.is_folded
        local l = #(paths[1])
        local primaryNode = paths[1][l]

        local foldmarker = icon_closed
        if not is_folded then
            foldmarker = icon_open
        end

        local text = primaryNode.label

        -- print primary column label
        if auditpanel_filename and nil ~= primaryNode['filename'] and primaryNode.filename ~= nil then
            if auditpanel_longnames then
                text = primaryNode.filename..':'..primaryNode.line
            else
                text = vim.fn.fnamemodify(primaryNode.filename, ':p:t')..':'..primaryNode.line
            end
        end
        hl = { CodeqlAuditPanelFoldIcon = {{ 0, string.len(foldmarker) }} }
        M.printToPanel(foldmarker..' '..text, hl)

        -- save the current issue in scaninfo.line_map
        local bufnr = vim.fn.bufnr(auditpanel_buffer_name)
        local curline = api.nvim_buf_line_count(bufnr)
        scaninfo.line_map[curline] = issue

        -- print nodes
        if not is_folded then
            M.printNodes(issue, 2)
        end
    end
end

function M.printNodes(issue, indent_level)

    local bufnr = vim.fn.bufnr(auditpanel_buffer_name)
    local curline = api.nvim_buf_line_count(bufnr)

    local paths = issue.paths

    -- paths
    local active_path = 1
    if #paths > 1 then
        if nil ~= scaninfo.line_map[curline] and nil ~= scaninfo.line_map[curline]['active_path'] then
            -- retrieve path info from scaninfo
            active_path = scaninfo.line_map[curline]['active_path']
        end
        local str = active_path..'/'..#paths
        if nil ~= scaninfo.line_map[curline + 1] then
            table.remove(scaninfo.line_map, curline + 1)
        end
        local text = string.rep(' ', indent_level)..'Path: '
        local hl = { CodeqlAuditPanelInfo = {{0, string.len(text)}} }
        M.printToPanel(text..str, hl)
    end
    local path = paths[active_path]

    --  print path nodes
    for _, node in ipairs(path) do
        M.printNode(node, indent_level)
    end
end

function M.printNode(node, indent_level)
    local text = ''
    local hl = {}

    -- mark
    local mark = string.rep(' ', indent_level)..node.mark..' '
    local mark_hl_name = ''
    if node.mark == '≔' then
        mark_hl_name = 'CodeqlAuditPanelLabel'
    else
        mark_hl_name = node.visitable and 'CodeqlAuditPanelVisitable' or 'CodeqlAuditPanelNonVisitable'
    end
    hl[mark_hl_name] = {{0, string.len(mark)}}

    -- text
    if nil ~= node['filename'] then
        if auditpanel_longnames then
            text = mark..node.filename..':'..node.line..' - '..node.label
        else
            text = mark..vim.fn.fnamemodify(node.filename, ':p:t')..':'..node.line..' - '..node.label
        end
        local sep_index = string.find(text, ' - ', 1, true)
        hl['CodeqlAuditPanelFile'] = {{ string.len(mark), sep_index }}
        hl['CodeqlAuditPanelSeparator'] = {{ sep_index, sep_index + 2 }}
    else
        text = mark..'['..node.label..']'
    end
    M.printToPanel(text, hl)

    -- save the current issue in scaninfo.sline map
    local bufnr = vim.fn.bufnr(auditpanel_buffer_name)
    local curline = api.nvim_buf_line_count(bufnr)
    scaninfo.line_map[curline] = node
end

-- Global functions
function ToggleFold()
    -- prevent highlighting from being off after adding/removing the help text
    api.nvim_command('match none')

    local c = vim.fn.line('.')
    while c >= 7 do
        if nil ~= scaninfo.line_map[c] then
            local node = scaninfo.line_map[c]
            if nil ~= node['is_folded'] then
                node['is_folded'] = not node['is_folded']
                M.renderKeepView(c)
                return
            end
        end
        c = c - 1
    end
end

function ToggleHelp()
    auditpanel_short_help = not auditpanel_short_help
    -- prevent highlighting from being off after adding/removing the help text
    M.renderKeepView()
end

function SetFoldLevel(level)
    for k, _ in pairs(scaninfo.line_map) do
        scaninfo.line_map[k]['is_folded'] = level
    end
    M.renderKeepView()
end

function ChangePath(offset)
    local line = vim.fn.line('.') - 1
    if nil == scaninfo.line_map[line] then
        return
    end

    local issue = scaninfo.line_map[line]

    if nil ~= issue['active_path'] then
        if issue['active_path'] == 1 and offset == -1 then
            scaninfo['line_map'][line]['active_path'] = #(issue.paths)
        elseif issue['active_path'] == (#issue.paths) and offset == 1 then
            scaninfo['line_map'][line]['active_path'] = 1
        else
            scaninfo['line_map'][line]['active_path'] = issue['active_path'] + offset
        end
        M.renderKeepView(line+1)
    end
end

function JumpToCode(stay_in_pane)
    if nil == scaninfo.line_map[vim.fn.line('.')] then
        return
    end

    local node = scaninfo.line_map[vim.fn.line('.')]

    if nil == node.visitable or not node.visitable then
        if nil ~= node.filename then
            print(node.filename)
        end
        return
    end

    -- save audit pane window
    local auditpanel_window = vim.fn.win_getid()

    -- go to main window
    M.goToMainWindow()

    api.nvim_command('e '..vim.fn.fnameescape(node.filename))

    -- mark current position so it can be jumped back to
    api.nvim_command("mark '")

    -- jump to the line where the tag is defined
    vim.fn.execute(node.line)

    -- highlight node
    local ns = api.nvim_create_namespace("codeql")
    -- TODO: clear codeql namespace in all buffers
    api.nvim_buf_clear_namespace(0, ns, 0, -1)
    -- TODO: multi-line range
    local startLine = node.url.startLine
    local startColumn = node.url.startColumn
    local endColumn = node.url.endColumn
    api.nvim_buf_add_highlight(0, ns, "CodeqlRange", startLine - 1, startColumn - 1, endColumn)

    -- TODO: need a way to clear highlights manually (command?)
    -- TODO: when changing line in audit panel (or cursorhold), check if we are over a node and
    -- if so, search for buffer based on filename, if there is one, do
    -- highlighting

    -- center the tag in the window
    api.nvim_command('normal! z.')
    api.nvim_command('normal! zv')

    if stay_in_pane then
        vim.fn.win_gotoid(auditpanel_window)
        api.nvim_command('redraw')
    end
end

function CloseAuditPanel()
    local win = M.getPanelWindow(auditpanel_buffer_name)
    vim.fn.nvim_win_close(win, true)
end

function ShowLongNames()
    auditpanel_longnames = not auditpanel_longnames
    M.renderKeepView(vim.fn.line('.'))
end

function ShowFilename()
    auditpanel_filename = not auditpanel_filename
    M.renderKeepView(vim.fn.line('.'))
end

return M
