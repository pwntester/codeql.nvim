" TODO port to lua: https://teukka.tech/vimloop.html

" global vars
let s:commandlist = []

" run chained commands asynchronously
function! codeql#job#runCommands(commands) abort
    let s:commandlist = a:commands
    call codeql#job#runCommandsHandler()
endfunction

" chained command handler
function! codeql#job#runCommandsHandler(...) abort

    if len(s:commandlist) > 0
        let l:cmd = s:commandlist[0]
        let s:commandlist = s:commandlist[1:]

        if l:cmd[0] == 'load_sarif'
            "  ['load_sarif', sarifPath, database, metadata]
            if filereadable(l:cmd[1])
                let l:results = luaeval("require('ql.loaders').loadSarifResults(_A,'".l:cmd[2]."')", l:cmd[1])
                call codeql#panel#renderAuditPanel(l:cmd[2], l:cmd[3], l:results)
                call codeql#job#runCommandsHandler()
            else
                echom "Cant find SARIF results at " . l:cmd[1]
                call codeql#panel#renderAuditPanel(l:cmd[2], l:cmd[3], {})
            endif
        elseif l:cmd[0] == 'load_json'
            " ['load_json', results, database, metadata]
            if filereadable(l:cmd[1])
                let l:results = luaeval("require('ql.loaders').loadJsonResults(_A,'".l:cmd[2]."')", l:cmd[1])
                call codeql#panel#renderAuditPanel(l:cmd[2], l:cmd[3], l:results)
                call codeql#job#runCommandsHandler()
            else
                echom "Cant find JSON results at " . l:cmd[1]
                call codeql#panel#renderAuditPanel(l:cmd[2], l:cmd[3], {})
            endif
        else
            if type(l:cmd) == v:t_list
                let l:cmd = join(l:cmd)
            endif
            call jobstart(l:cmd, {'on_exit': function('g:codeql#job#runCommandsHandler')})
        endif
    endif
endfunction

