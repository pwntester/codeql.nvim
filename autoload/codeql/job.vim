" TODO port to lua: https://teukka.tech/vimloop.html

" global vars
let s:testpanel_buffer_timer = 0
let s:commandlist = []

" run chained commands asynchronously
function! codeql#job#runCommands(commands)
    let s:commandlist = a:commands
    call codeql#job#runCommandsHandler()
endfunction

" chained command handler
function! codeql#job#runCommandsHandler(...)

    " flush the TestPanel buffer
    if s:testpanel_buffer_timer != 0
        call timer_stop(s:testpanel_buffer_timer)
        call codeql#panel#flushTestPanel()
        let s:testpanel_buffer_timer = 0
    endif

    if len(s:commandlist) > 0
        let l:cmd = s:commandlist[0]
        let s:commandlist = s:commandlist[1:]

        if l:cmd[0] == 'process_results'
            call codeql#show_results(l:cmd[1], l:cmd[2], l:cmd[3], 0)
            call codeql#job#runCommandsHandler()
        else
            " buffer stderr and stdout and flush to TestPanel every 1 seconds
            let s:testpanel_buffer = []
            let s:testpanel_buffer_timer = timer_start(1000, function('codeql#panel#flushTestPanel'), {'repeat':-1})
            if type(l:cmd) == v:t_list
                let l:cmd = join(l:cmd)
            endif
            call codeql#panel#printToTestPanel('Running: '.l:cmd)
            call jobstart(l:cmd, {
                \ 'on_stdout': function('g:codeql#panel#printHandler'),
                \ 'on_stderr': function('g:codeql#panel#printHandler'),
                \ 'on_exit': function('g:codeql#job#runCommandsHandler'),
            \ })
        endif
    else
        " flush the output buffer
        if s:testpanel_buffer_timer != 0
            call timer_stop(s:testpanel_buffer_timer)
            call codeql#panel#flushTestPanel()
            let s:testpanel_buffer_timer = 0
        endif
        call codeql#panel#printToTestPanel(' ')
        call codeql#panel#printToTestPanel('Done!')
    endif
endfunction

