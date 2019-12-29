" vars
let s:testpanel_buffer_name = '__TestPanel__'
let s:auditpanel_buffer_name = '__AuditPanel__'
let s:testpanel_buffer = []
let s:testpanel_jumpinfo = {}
let s:auditpanel_pos = 'right'
let s:auditpanel_width = 50
let s:auditpanel_indent = 1
let s:auditpanel_longnames = 0
let s:auditpanel_filename = 1
let s:auditpanel_short_help = 1
let s:issues = {}
let s:scaninfo = {}
let s:database = ''
let s:metadata = {}
let s:is_maximized = 0
let s:auditpanel_iconchars = ['▶', '▼']
let s:icon_closed = s:auditpanel_iconchars[0]
let s:icon_open = s:auditpanel_iconchars[1]

" get buffer window
function! codeql#panel#getPanelWindow(buffer_name) abort
    let l:bufnr = bufnr(a:buffer_name)
    for w in nvim_list_wins()
        if nvim_win_get_buf(w) == l:bufnr
            return w 
        endif
    endfor
    return v:null
endfunction

" open test panel window
function! codeql#panel#openTestPanel() abort

    " check if test pane is already present
    if bufwinnr(s:testpanel_buffer_name) != -1
        return
    endif

    " get current win id
    let current_window = win_getid()

    " go to main window
    call codeql#panel#goToMainWindow()

    " split
    execute 'silent keepalt rightbelow 10 split ' . s:testpanel_buffer_name

    " go to original window
    call win_gotoid(l:current_window)
    
    " buffer options 
    let l:bufnr = bufnr(s:testpanel_buffer_name)
    call nvim_buf_set_option(l:bufnr, 'filetype', 'codeqltestpanel')
    call nvim_buf_set_option(l:bufnr, 'buftype', 'nofile')
    call nvim_buf_set_option(l:bufnr, 'bufhidden', 'hide')
    call nvim_buf_set_option(l:bufnr, 'swapfile', v:false)
    call nvim_buf_set_option(l:bufnr, 'buflisted', v:false)
    call nvim_buf_set_keymap(l:bufnr, 'n', '<CR>', ':call codeql#panel#jumpToCode(0)<CR>', {'script': v:true, 'silent': v:true})
    call nvim_buf_set_keymap(l:bufnr, 'n', 'p', ':call codeql#panel#jumpToCode(1)<CR>', {'script': v:true, 'silent': v:true})

    " window options
    let l:win = codeql#panel#getPanelWindow(s:testpanel_buffer_name)
    call nvim_win_set_option(l:win, 'wrap', v:false)
    call nvim_win_set_option(l:win, 'number', v:false)
    call nvim_win_set_option(l:win, 'foldenable', v:false)
    call nvim_win_set_option(l:win, 'winfixheight', v:true)
    call nvim_win_set_option(l:win, 'concealcursor', 'nvi')
    call nvim_win_set_option(l:win, 'conceallevel', 3)
    call nvim_win_set_option(l:win, 'signcolumn', 'yes')
endfunction

" close test panel
function! codeql#panel#closeTestPanel() abort
    let l:win = codeql#panel#getPanelWindow(s:testpanel_buffer_name)
    call nvim_win_close(l:win, v:true)
endfunction

" clear test panel
function! codeql#panel#clearTestPanel() abort
    let s:testpanel_buffer = []
    let s:testpanel_buffer_timer = 0
    let l:bufnr = bufnr(s:testpanel_buffer_name)
    if l:bufnr < 0
        return
    endif
    call nvim_buf_set_lines(l:bufnr, 0, -1, v:false, [""])
    let l:win = codeql#panel#getPanelWindow(s:testpanel_buffer_name)
    call nvim_win_set_cursor(l:win, [1, 0])
endfunction

" open audit panel
function! codeql#panel#openAuditPanel() abort

    " check if audit pane is already present
    if bufwinnr(s:auditpanel_buffer_name) != -1
        return
    endif

    " prepare split arguments
    if s:auditpanel_pos == 'right'
        let pos = 'botright'
    elseif s:auditpanel_pos == 'left'
        let pos = 'topleft'
    else
        echo("Incorrect s:auditpanel_pos value")
        return
    end

    " get current win id
    let current_window = win_getid()

    " go to main window
    call codeql#panel#goToMainWindow()

    " split
    exe 'silent keepalt ' . pos . ' vertical ' . s:auditpanel_width . 'split '.s:auditpanel_buffer_name
    
    " go to original window
    call win_gotoid(l:current_window)

    " buffer options 
    let l:bufnr = bufnr(s:auditpanel_buffer_name)
    call nvim_buf_set_option(l:bufnr, 'filetype', 'codeqlauditpanel')
    call nvim_buf_set_option(l:bufnr, 'buftype', 'nofile')
    call nvim_buf_set_option(l:bufnr, 'bufhidden', 'hide')
    call nvim_buf_set_option(l:bufnr, 'swapfile', v:false)
    call nvim_buf_set_option(l:bufnr, 'buflisted', v:false)

    call nvim_buf_set_keymap(l:bufnr, 'n', 'o', ':call codeql#panel#toggleFold()<CR>', {'script': v:true, 'silent': v:true})
    call nvim_buf_set_keymap(l:bufnr, 'n', '<CR>', ':call codeql#panel#jumpToTag(0)<CR>', {'script': v:true, 'silent': v:true})
    call nvim_buf_set_keymap(l:bufnr, 'n', 'p', ':call codeql#panel#jumpToTag(1)<CR>', {'script': v:true, 'silent': v:true})
    call nvim_buf_set_keymap(l:bufnr, 'n', 'L', ':call codeql#panel#showLongNames()<CR>', {'script': v:true, 'silent': v:true})
    call nvim_buf_set_keymap(l:bufnr, 'n', 'f', ':call codeql#panel#showFilename()<CR>', {'script': v:true, 'silent': v:true})
    call nvim_buf_set_keymap(l:bufnr, 'n', 'H', ':call codeql#panel#toggleHelp()<CR>', {'script': v:true, 'silent': v:true})
    call nvim_buf_set_keymap(l:bufnr, 'n', 'q', ':call codeql#panel#closeAuditPanel()<CR>', {'script': v:true, 'silent': v:true})
    call nvim_buf_set_keymap(l:bufnr, 'n', 'O', ':call codeql#panel#setFoldLevel(0)<CR>', {'script': v:true, 'silent': v:true})
    call nvim_buf_set_keymap(l:bufnr, 'n', 'c', ':call codeql#panel#setFoldLevel(1)<CR>', {'script': v:true, 'silent': v:true})
    call nvim_buf_set_keymap(l:bufnr, 'n', 'P', ':call codeql#panel#changePath(-1)<CR>', {'script': v:true, 'silent': v:true})
    call nvim_buf_set_keymap(l:bufnr, 'n', 'N', ':call codeql#panel#changePath(1)<CR>', {'script': v:true, 'silent': v:true})

    " window options
    let l:win = codeql#panel#getPanelWindow(s:auditpanel_buffer_name)
    call nvim_win_set_option(l:win, 'wrap', v:false)
    call nvim_win_set_option(l:win, 'number', v:false)
    call nvim_win_set_option(l:win, 'relativenumber', v:false)
    call nvim_win_set_option(l:win, 'foldenable', v:false)
    call nvim_win_set_option(l:win, 'winfixwidth', v:true)
    call nvim_win_set_option(l:win, 'concealcursor', 'nvi')
    call nvim_win_set_option(l:win, 'conceallevel', 3)
    call nvim_win_set_option(l:win, 'signcolumn', 'yes')

endfunction

" close audit panel window
function! codeql#panel#closeAuditPanel() abort
    let l:win = codeql#panel#getPanelWindow(s:auditpanel_buffer_name)
    call nvim_win_close(l:win, v:true)
endfunction

" flush buffer to test panel
function! codeql#panel#flushTestPanel(...)
  call codeql#panel#printToTestPanel(s:testpanel_buffer)
  let s:testpanel_buffer = []
endfunction

" show long names
function! codeql#panel#showLongNames() abort
    let s:auditpanel_longnames = !s:auditpanel_longnames
    call codeql#panel#renderKeepView(line('.'))
endfunction

" show filename
function! codeql#panel#showFilename() abort
    let s:auditpanel_filename = !s:auditpanel_filename
    call codeql#panel#renderKeepView(line('.'))
endfunction

" prints to window
function! codeql#panel#printHandler(job_id, data, event)
  if a:event == 'stdout' || a:event == 'stderr'
    for i in a:data
        let l:text = substitute(l:i, "\n", "", "g")
        call add(s:testpanel_buffer, l:text)
    endfor
  endif
endfunction

" goto main window
function! codeql#panel#goToMainWindow() abort
    let l:widerwin = 0
    let l:widerwidth = 0
    for w in nvim_list_wins()
        if nvim_win_get_width(w) > l:widerwidth
            let l:widerwin = w
            let l:widerwidth = nvim_win_get_width(w)
        endif
    endfor
    if l:widerwin> -1
        call win_gotoid(l:widerwin)
    endif
endfunction

" print to Audit Panel
function! codeql#panel#printToAuditPanel(text, ...)
    let l:bufnr = bufnr(s:auditpanel_buffer_name)
    call nvim_buf_set_lines(l:bufnr, -1, -1, v:true, [a:text])
    let l:matches = a:0 > 0 ? a:1 : {} 
    for [hlgroup, groups] in items(l:matches)
        for group in groups
            let linenr = nvim_buf_line_count(l:bufnr)-1
            call nvim_buf_add_highlight(l:bufnr, g:fortify_auditpane_ns, hlgroup, linenr, group[0], group[1])
        endfor
    endfor
endfunction

" prints to Test Panel
function! codeql#panel#printToTestPanel(text, ...) abort
    " emulate default argument values
    let l:text     = a:text
    let l:filename = a:0 > 0 ? a:1 : ""
    let l:line     = a:0 > 1 ? a:2 : -1

    let l:bufnr = bufnr(s:testpanel_buffer_name)
    if l:bufnr < 0
        call codeql#panel#openTestPanel()
        let l:bufnr = bufnr(s:testpanel_buffer_name)
    endif
 
    " store line and file info and generate msg to print
    if !empty(l:filename) && filereadable(l:filename) && l:line > -1
        let l:curline = nvim_buf_line_count(l:bufnr) + 1
        let l:jump = {}
        let l:jump['line'] = l:line
        let l:jump['filename'] = l:filename
        let s:testpanel_jumpinfo[l:curline] = l:jump
    endif

    " print strings
    if type(l:text) == 1
        if !empty(l:text)
            call nvim_buf_set_lines(l:bufnr, -1, -1, v:true, [l:text])
        endif
    " print lists
    elseif type(l:text) == 3
        call filter(l:text, {idx, val -> !empty(val)})
        call nvim_buf_set_lines(l:bufnr, -1, -1, v:true, l:text)
    endif

    " find window holding TestPanel
    let l:win = codeql#panel#getPanelWindow(s:testpanel_buffer_name)
    let l:count = nvim_buf_line_count(l:bufnr)
    if l:count > nvim_win_get_height(l:win) && nvim_win_get_cursor(l:win)[0] < l:count 
        " scroll to bottom if user has not move cursor
        call nvim_win_set_cursor(l:win, [l:count, 0])
    endif
endfunction

" jump to code 
function! codeql#panel#jumpToCode(stay_in_pane) abort
    if !has_key(s:testpanel_jumpinfo, line('.'))
        echom "No info for current line: " . line('.')
        return
    endif

    let l:info = s:testpanel_jumpinfo[line('.')]
    if empty(l:info) || !has_key(l:info, 'filename')
        echom "No info for current line: " . line('.')
        return
    endif

    " save test window
    let l:testpanel_window = win_getid()

    " go to main window
    call codeql#panel#goToMainWindow()

    execute 'e ' . fnameescape(info.filename)

    " Mark current position so it can be jumped back to
    mark '

    " jump to the line where the tag is defined. Don't use the search pattern
    " since it doesn't take the scope into account and thus can fail if tags
    " with the same name are defined in different scopes (e.g. classes)
    execute info.line

    " center the tag in the window
    normal! z.
    normal! zv

    if a:stay_in_pane
        call win_gotoid(l:testpanel_window)
        redraw
    endif
endfunction

" render audit panel
function! codeql#panel#renderAuditPanel(database, metadata, issues) abort
    if nvim_buf_get_option(0, 'filetype') == s:testpanel_buffer_name
        execute 'wincmd p'
    endif
    call codeql#panel#openAuditPanel()
    let s:database = a:database
    let s:metadata = a:metadata
    let s:issues = a:issues
    let s:scaninfo = {'line_map': {}}
    call codeql#panel#renderContent()
endfunction

" render audit panel content
function! codeql#panel#renderContent() abort
    let l:bufnr = bufnr(s:auditpanel_buffer_name)
    call nvim_buf_set_option(l:bufnr, 'modifiable', v:true)
    call nvim_buf_set_lines(l:bufnr, 0, -1, v:false, [])
    call codeql#panel#printHelp()
    if !empty(s:issues)
        call codeql#panel#printIssues()
    else
        call codeql#panel#printToAuditPanel('" No results found.')
    endif
    call nvim_buf_set_option(l:bufnr, 'modifiable', v:false)
    let l:win = codeql#panel#getPanelWindow(s:auditpanel_buffer_name)
    call nvim_win_set_cursor(l:win, [8, 0])
endfunction

" print issues
function! codeql#panel#printIssues() abort

    let l:hl = {"CodeqlAuditPanelInfo": [[0,len('Database:')]]}
    let l:dbname = split(s:database, '/')[-1:][0]
    call codeql#panel#printToAuditPanel('Database: '.l:dbname, l:hl)

    let l:hl = {"CodeqlAuditPanelInfo": [[0,len('Issues:')]]}
    call codeql#panel#printToAuditPanel('Issues:   '.len(s:issues), l:hl)

    if has_key(s:metadata, 'kind')
        let l:hl = {"CodeqlAuditPanelInfo": [[0,len('Kind:')]]}
        call codeql#panel#printToAuditPanel('Kind:     '.s:metadata['kind'], l:hl)
    endif
    call codeql#panel#printToAuditPanel('')

    " print issue labels
    for l:issue in s:issues

        let l:paths = l:issue.paths
        let l:is_folded = l:issue.is_folded

        for l:node in l:paths[0]
            if l:node.filename != v:null
                " first node with filename info
                let l:primaryNode = l:node
                break
            endif
        endfor
        if !exists("l:primaryNode")
            " all nodes are labels
            let l:primaryNode = l:paths[0][0]
            let l:primaryNode.filename = "No file info"
        endif

        if l:is_folded
            let l:foldmarker = s:icon_closed
        else
            let l:foldmarker = s:icon_open
        endif

        " print primary column label
        if s:auditpanel_filename
            if s:auditpanel_longnames
                let l:text = l:primaryNode.filename.':'.l:primaryNode.line
            else
                let l:text = fnamemodify(l:primaryNode.filename, ':p:t').':'.l:primaryNode.line
            endif
        else
            let l:text = l:primaryNode.label
        endif
        let l:hl = {"CodeqlAuditPanelFoldIcon": [[0,len(l:foldmarker)]]}
        call codeql#panel#printToAuditPanel(l:foldmarker.' '.l:text, l:hl)

        " save the current issue in scaninfo.line_map
        let l:bufnr = bufnr(s:auditpanel_buffer_name)
        let l:curline = nvim_buf_line_count(l:bufnr)
        let s:scaninfo.line_map[l:curline] = l:issue

        if !l:is_folded
            " print issues
            call codeql#panel#printNodes(l:issue, 2)
        endif
    endfor
endfunction

function! codeql#panel#printNodes(issue, indent_level) abort

    let l:bufnr = bufnr(s:auditpanel_buffer_name)
    let l:curline = nvim_buf_line_count(l:bufnr)

    let l:paths = a:issue.paths
    let l:is_folded = a:issue.is_folded

    " paths
    let l:active_path = 0 
    if len(l:paths) > 1
        if has_key(s:scaninfo.line_map, l:curline) && has_key(s:scaninfo.line_map[l:curline], 'active_path')
            " retrieve path info from scaninfo
            let l:active_path = s:scaninfo.line_map[l:curline]['active_path']
        endif
        let l:str = (l:active_path + 1) . '/' . len(l:paths)
        if has_key(s:scaninfo.line_map, l:curline + 1)
            call remove(s:scaninfo.line_map, l:curline + 1) 
        endif
        let l:text = repeat(' ', a:indent_level).'Path: '
        let l:hl = {"CodeqlAuditPanelInfo": [[0,len(l:text)]]}
        call codeql#panel#printToAuditPanel(l:text.l:str, l:hl)
    endif
    let l:path = l:paths[l:active_path]

    " print path nodes
    for l:node in l:path
        call codeql#panel#printNode(l:node, a:indent_level)
    endfor
endfunction

" print node
function! codeql#panel#printNode(node, indent_level) abort
    if a:node.mark == '≔'
        let l:icon_hl = 'CodeqlAuditPanelLabel'
    else
        let l:icon_hl = a:node.visitable ? 'CodeqlAuditPanelVisitable' : 'CodeqlAuditPanelNonVisitable'
    end
    let l:mark = repeat(' ', a:indent_level).a:node.mark.' '
    let l:hl = {
        \ icon_hl: [[0,len(l:mark)]]
        \ }
    if a:node.filename != v:null
        if s:auditpanel_longnames
            let l:text = l:mark.a:node.filename.':'.a:node.line.' - '.a:node.label
        else
            let l:text = l:mark.fnamemodify(a:node.filename, ':p:t').':'.a:node.line.' - '.a:node.label
        endif
        let l:hl["CodeqlAuditPanelFile"] = [[len(l:mark), stridx(l:text, '-')]]
        let l:hl["CodeqlAuditPanelSeparator"] = [[stridx(l:text, '-'), stridx(l:text, '-')+1]]
    else
        let l:text = l:mark.'['.a:node.label.']'
    endif
    call codeql#panel#printToAuditPanel(l:text, l:hl)
    " save the current issue in scaninfo.sline map
    let l:bufnr = bufnr(s:auditpanel_buffer_name)
    let l:curline = nvim_buf_line_count(l:bufnr)
    let s:scaninfo.line_map[l:curline] = a:node
endfunction

" print help 
function! codeql#panel#printHelp() abort
    if s:auditpanel_short_help
        call codeql#panel#printToAuditPanel('" Press H for help')
        call codeql#panel#printToAuditPanel('')
    elseif !s:auditpanel_short_help
        call codeql#panel#printToAuditPanel('" --------- General ---------')
        call codeql#panel#printToAuditPanel('" <CR>: Jump to tag definition')
        call codeql#panel#printToAuditPanel('" p: As above, but stay in AuditPane')
        call codeql#panel#printToAuditPanel('" L: Show long file names')
        call codeql#panel#printToAuditPanel('" P: Previous path')
        call codeql#panel#printToAuditPanel('" N: Next path')
        call codeql#panel#printToAuditPanel('"')
        call codeql#panel#printToAuditPanel('" ---------- Folds ----------')
        call codeql#panel#printToAuditPanel('" o: Toggle fold')
        call codeql#panel#printToAuditPanel('" O: Open all folds')
        call codeql#panel#printToAuditPanel('" c: Close all folds')
        call codeql#panel#printToAuditPanel('"')
        call codeql#panel#printToAuditPanel('" ---------- Misc -----------')
        call codeql#panel#printToAuditPanel('" q: Close window')
        call codeql#panel#printToAuditPanel('" H: Toggle help')
        call codeql#panel#printToAuditPanel('')
    endif
endfunction

" render keep view
function! codeql#panel#renderKeepView(...) abort
    if a:0 == 1
        let line = a:1
    else
        let line = line('.')
    endif

    " Called from toggleFold commands, so within AuditPane buffer
    let curcol  = col('.')
    let topline = line('w0')

    call codeql#panel#renderContent()

    let scrolloff_save = &scrolloff
    set scrolloff=0

    call cursor(topline, 1)
    normal! zt
    call cursor(line, curcol)

    let &scrolloff = scrolloff_save
    redraw
endfunction

" compare strings
function! codeql#panel#strcmp(str1, str2)
    if a:str1 < a:str2
        return -1
    elseif a:str1 == a:str2
        return 0
    else
        return 1
    endif
endfunction

" sort by name
function! codeql#panel#sortByName(i1, i2)
    let filename1 = a:i1.filename
    let filename2 = a:i2.filename
    let line1 = a:i1.line + 0
    let line2 = a:i2.line + 0

    if filename1 == filename2
        return line1 - line2
    else
        return codeql#panel#strcmp(filename1, filename2)
    endif
endfunction

" jump to tag
function! codeql#panel#jumpToTag(stay_in_pane) abort
    if !has_key(s:scaninfo.line_map, line('.'))
        return
    endif
    let l:node = s:scaninfo.line_map[line('.')]

    if !exists('l:node.visitable') || !l:node.visitable
        if has_key(l:node, 'filename') && l:node.filename != v:null
            echom l:node.filename
        endif
        return
    endif

    " save audit pane window
    let l:auditpanel_window = win_getid()

    " go to main window
    call codeql#panel#goToMainWindow()

    execute 'e ' . fnameescape(l:node.filename)

    " mark current position so it can be jumped back to
    mark '

    " jump to the line where the tag is defined
    execute l:node.line

    " highlight node
    let ns = nvim_create_namespace("codeql")
    " TODO: clear codeql namespace in all buffers
    call nvim_buf_clear_namespace(0, ns, 0, -1)
    if l:node.orig.url.startLine == l:node.orig.url.endLine
        call nvim_buf_add_highlight(0, ns, "CodeqlRange", l:node.orig.url.startLine-1, l:node.orig.url.startColumn-1, l:node.orig.url.endColumn)
        " TODO: multi-line range
    endif

    " TODO: need a way to clear highlights manually (command?)
    " TODO: when changing line in audit panel (or cursorhold), check if we are over a node and
    " if so, search for buffer based on filename, if there is one, do
    " highlighting

    " center the tag in the window
    normal! z.
    normal! zv

    if a:stay_in_pane
        call win_gotoid(l:auditpanel_window)
        redraw
    endif
endfunction

" toggle help
function! codeql#panel#toggleHelp() abort
    let s:auditpanel_short_help = !s:auditpanel_short_help
    " prevent highlighting from being off after adding/removing the help text
    match none
    call codeql#panel#renderContent()
    execute 1
    redraw
endfunction

" toggle fold
function! codeql#panel#toggleFold() abort
    if !has_key(s:scaninfo.line_map, line('.')) | return | endif

    " prevent highlighting from being off after adding/removing the help text
    match none

    let l:node = s:scaninfo.line_map[line('.')]
    if has_key(l:node, 'is_folded')
        let l:node['is_folded'] = !l:node['is_folded']
    else
        return
    endif
    call codeql#panel#renderKeepView(line('.'))
endfunction

" set fold level
function! codeql#panel#setFoldLevel(level) abort
    for l:result in values(s:scaninfo.line_map)
        let l:result.is_folded = a:level
    endfor
    call codeql#panel#renderContent()
endfunction

" change path
function! codeql#panel#changePath(offset) abort
    let l:line = line('.') - 1
    if !has_key(s:scaninfo.line_map, l:line)
        return
    endif
    let l:issue = s:scaninfo.line_map[l:line]
        

    if has_key(l:issue, 'active_path')
        if l:issue.active_path == 0 && a:offset == -1
            let l:issue['active_path'] = len(l:issue.paths) - 1
        elseif l:issue.active_path == len(l:issue.paths) - 1 && a:offset == 1
            let l:issue['active_path'] = 0
        else
            let l:issue['active_path'] = l:issue.active_path +  a:offset
        endif
        call codeql#panel#renderKeepView(l:line+1)
    endif
endfunction
