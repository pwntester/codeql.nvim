local vim = vim
local api = vim.api

local panel_buffer_name = '__CodeQLPanel__'
local panel_pos = 'right'
local panel_width = 50
local panel_short_help = true
local icon_closed = '▶'
local icon_open = '▼'

local database = ''
local issues = {}
local scaninfo = {}

-- local functions
local function print_to_panel(text, matches)
    local bufnr = vim.fn.bufnr(panel_buffer_name)
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

local function get_panel_window(buffer_name)
    local bufnr = vim.fn.bufnr(buffer_name)
    for _, w in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_get_buf(w) == bufnr then
            return w
        end
    end
    return nil
end

local function go_to_main_window()
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

local function is_filtered(filter, issue)
    local f, err = loadstring("return function(issue) return " .. filter .. " end")
    if f then return f()(issue) else return f, err end
end

local function filter_issues(filter_str)
    for _, issue in ipairs(issues) do
        if not is_filtered(filter_str, issue) then
            issue.hidden = true
        end
    end
end

local function unhide_issues()
    for _, issue in ipairs(issues) do
        issue.hidden = false
    end
end

local function print_help()
    if panel_short_help then
        print_to_panel('" Press H for help')
        print_to_panel('')
    else
        print_to_panel('" --------- General ---------')
        print_to_panel('" <CR>: Jump to tag definition')
        print_to_panel('" p: As above, but dont change window')
        print_to_panel('" P: Previous path')
        print_to_panel('" n: Next path')
        print_to_panel('"')
        print_to_panel('" ---------- Folds ----------')
        print_to_panel('" f: Label filter')
        print_to_panel('" F: Generic filter')
        print_to_panel('" c: Clear filter')
        print_to_panel('"')
        print_to_panel('" ---------- Folds ----------')
        print_to_panel('" o: Toggle fold')
        print_to_panel('" t: Open all folds')
        print_to_panel('" T: Close all folds')
        print_to_panel('"')
        print_to_panel('" ---------- Misc -----------')
        print_to_panel('" q: Close window')
        print_to_panel('" H: Toggle help')
        print_to_panel('')
    end
end

local function print_node(node, indent_level)
    local text = ''
    local hl = {}

    -- mark
    local mark = string.rep(' ', indent_level)..node.mark..' '
    local mark_hl_name = ''
    if node.mark == '≔' then
        mark_hl_name = 'CodeqlPanelLabel'
    else
        mark_hl_name = node.visitable and 'CodeqlPanelVisitable' or 'CodeqlPanelNonVisitable'
    end
    hl[mark_hl_name] = {{0, string.len(mark)}}

    -- text
    if nil ~= node['filename'] then
        if vim.g.codeql_panel_longnames then
            text = mark..node.filename..':'..node.line..' - '..node.label
        else
            text = mark..vim.fn.fnamemodify(node.filename, ':p:t')..':'..node.line..' - '..node.label
        end
        local sep_index = string.find(text, ' - ', 1, true)
        hl['CodeqlPanelFile'] = {{ string.len(mark), sep_index }}
        hl['CodeqlPanelSeparator'] = {{ sep_index, sep_index + 2 }}
    else
        text = mark..'['..node.label..']'
    end
    print_to_panel(text, hl)

    -- save the current issue in scaninfo.sline map
    local bufnr = vim.fn.bufnr(panel_buffer_name)
    local curline = api.nvim_buf_line_count(bufnr)
    scaninfo.line_map[curline] = node
end

local function print_nodes(issue, indent_level)

    local bufnr = vim.fn.bufnr(panel_buffer_name)
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
        local hl = { CodeqlPanelInfo = {{0, string.len(text)}} }
        print_to_panel(text..str, hl)
    end
    local path = paths[active_path]

    --  print path nodes
    for _, node in ipairs(path) do
        print_node(node, indent_level)
    end
end

local function print_issues()

    local hl = { CodeqlPanelInfo = {{0, string.len('Database:')}} }
    local index = string.find(database, '/[^/]*$')
    if nil ~= index then
        print_to_panel('Database: '..string.sub(database, index + 1), hl)
    else
        print_to_panel('Database: '..database, hl)
    end


    hl = { CodeqlPanelInfo = {{0, string.len('Issues:')}} }
    print_to_panel('Issues:   '..table.getn(issues), hl)

    print_to_panel('')

    -- print issue labels
    for _, issue in ipairs(issues) do
        if issue.hidden then goto continue end
        local is_folded = issue.is_folded

        local foldmarker = icon_closed
        if not is_folded then
            foldmarker = icon_open
        end

        local text = issue.label
        hl = { CodeqlPanelFoldIcon = {{ 0, string.len(foldmarker) }} }
        print_to_panel(foldmarker..' '..text, hl)

        -- save the current issue in scaninfo.line_map
        local bufnr = vim.fn.bufnr(panel_buffer_name)
        local curline = api.nvim_buf_line_count(bufnr)
        scaninfo.line_map[curline] = issue

        -- print nodes
        if not is_folded then
            print_nodes(issue, 2)
        end
        ::continue::
    end
end

local function render_content()
    local bufnr = vim.fn.bufnr(panel_buffer_name)
    if bufnr == -1 then print('Error opening CodeQL panel'); return end
    api.nvim_buf_set_option(bufnr, 'modifiable', true)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    print_help()
    if #issues >0 then
        print_issues()
        local win = get_panel_window(panel_buffer_name)
        local lcount = api.nvim_buf_line_count(bufnr)
        api.nvim_win_set_cursor(win, {math.min(7,lcount), 0})
    else
        print_to_panel('No results found.')
    end
    api.nvim_buf_set_option(bufnr, 'modifiable', false)
    print(' ')
end

local function open_codeql_panel()

    -- check if audit pane is already opened
    if vim.fn.bufwinnr(panel_buffer_name) ~= -1 then
        return
    end

    -- prepare split arguments
    local pos = ''
    if panel_pos == 'right' then
        pos = 'botright'
    elseif panel_pos == 'left' then
        pos = 'topleft'
    else
        print('Incorrect panel_pos value')
        return
    end

    -- get current win id
    local current_window = vim.fn.win_getid()

    -- go to main window
    go_to_main_window()

    -- split
    vim.fn.execute('silent keepalt '..pos..' vertical '..panel_width..'split '..panel_buffer_name)

    -- go to original window
    vim.fn.win_gotoid(current_window)

    -- buffer options
    local bufnr = vim.fn.bufnr(panel_buffer_name)

    api.nvim_buf_set_option(bufnr, 'filetype', 'codeqlpanel')
    api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
    api.nvim_buf_set_option(bufnr, 'bufhidden', 'hide')
    api.nvim_buf_set_option(bufnr, 'swapfile', false)
    api.nvim_buf_set_option(bufnr, 'buflisted', false)

    api.nvim_buf_set_keymap(bufnr, 'n', 'o', '<Cmd>lua require("ql.panel").toggle_fold()<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', '<Cmd>lua require("ql.panel").jump_to_code(false)<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'p', '<Cmd>lua require("ql.panel").jump_to_code(true)<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', '<S-h>', '<Cmd>lua require("ql.panel").toggle_help()<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'q', '<Cmd>lua require("ql.panel").close_codeql_panel()<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 't', '<Cmd>lua require("ql.panel").set_fold_level(false)<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', '<S-T>', '<Cmd>lua require("ql.panel").set_fold_level(true)<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', '<S-p>', '<Cmd>lua require("ql.panel").change_path(-1)<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'n', '<Cmd>lua require("ql.panel").change_path(1)<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', 'f', '<Cmd>lua require("ql.panel").label_filter()<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', '<S-f>', '<Cmd>lua require("ql.panel").generic_filter()<CR>', { script = true,  silent = true})
    api.nvim_buf_set_keymap(bufnr, 'n', '<S-c>', '<Cmd>lua require("ql.panel").clear_filter()<CR>', { script = true,  silent = true})

    -- window options
    local win = get_panel_window(panel_buffer_name)
    api.nvim_win_set_option(win, 'wrap', false)
    api.nvim_win_set_option(win, 'number', false)
    api.nvim_win_set_option(win, 'relativenumber', false)
    api.nvim_win_set_option(win, 'foldenable', false)
    api.nvim_win_set_option(win, 'winfixwidth', true)
    api.nvim_win_set_option(win, 'concealcursor', 'nvi')
    api.nvim_win_set_option(win, 'conceallevel', 3)
    api.nvim_win_set_option(win, 'signcolumn', 'yes')
end

local function render_keep_view(line)
    if line == nil then line = vim.fn.line('.') end

    -- called from toggle_fold commands, so within panel buffer
    local curcol = vim.fn.col('.')
    local topline = vim.fn.line('w0')

    render_content()

    local scrolloff_save = api.nvim_get_option('scrolloff')
    api.nvim_command('set scrolloff=0')

    vim.fn.cursor(topline, 1)
    api.nvim_command('normal! zt')
    vim.fn.cursor(line, curcol)

    api.nvim_command('let &scrolloff = '..scrolloff_save)
    api.nvim_command('redraw')
end

-- exported functions

local M = {}

function M.clear_filter()
    unhide_issues()
    render_content()
end

function M.label_filter()
    local pattern = vim.fn.input("Pattern: ")
    unhide_issues()
    filter_issues("string.match(string.lower(issue.label), string.lower('"..pattern.."')) ~= nil")
    render_content()
end

function M.generic_filter()
    local pattern = vim.fn.input("Pattern: ")
    unhide_issues()
    filter_issues(pattern)
    render_content()
end

function M.toggle_fold()
    -- prevent highlighting from being off after adding/removing the help text
    api.nvim_command('match none')

    local c = vim.fn.line('.')
    while c >= 7 do
        if nil ~= scaninfo.line_map[c] then
            local node = scaninfo.line_map[c]
            if nil ~= node['is_folded'] then
                node['is_folded'] = not node['is_folded']
                render_keep_view(c)
                return
            end
        end
        c = c - 1
    end
end

function M.toggle_help()
    panel_short_help = not panel_short_help
    -- prevent highlighting from being off after adding/removing the help text
    render_keep_view()
end

function M.set_fold_level(level)
    for k, _ in pairs(scaninfo.line_map) do
        scaninfo.line_map[k]['is_folded'] = level
    end
    render_keep_view()
end

function M.change_path(offset)
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
        render_keep_view(line+1)
    end
end

function M.jump_to_code(stay_in_pane)
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
    local panel_window = vim.fn.win_getid()

    -- go to main window
    go_to_main_window()

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
        vim.fn.win_gotoid(panel_window)
        api.nvim_command('redraw')
    end
end

function M.close_codeql_panel()
    local win = get_panel_window(panel_buffer_name)
    vim.fn.nvim_win_close(win, true)
end

function M.render(_database, _issues)
    open_codeql_panel()

    scaninfo = { line_map =  {} }

    issues = _issues

    -- sort
    table.sort(issues, function(a,b)
        return a.label < b.label
    end)

    if string.sub(_database, -1) == "/" then
        database = string.sub(_database, 1, -2)
    else
        database = _database
    end

    render_content()
end

return M
