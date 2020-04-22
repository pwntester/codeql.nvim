let s:database = ''
" let s:history = []

function! codeql#extractQueryMetadata(query)
    let l:metadata = system('codeql resolve metadata --format=json '.a:query)
    return json_decode(l:metadata)
endfunction

function! codeql#setDatabase(database) abort
    let s:database = fnamemodify(a:database, ':p')
    if !isdirectory(s:database)
        echom 'Incorrect database'
        return
    else
        echom 'Database set to '.s:database
    endif
endfunction

function! codeql#runQuery(quick_eval) abort
    if s:database == ''
        echom 'Missing database. Use SetDatabase command'
        return
    endif

    if !isdirectory(s:database.'/src') && filereadable(s:database.'/src.zip')
        execute 'silent !mkdir '.s:database.'/src'
        execute 'silent !unzip '.s:database.'/src.zip -d '.s:database.'/src'
    endif

    let l:queryPath = expand('%:p')

	" [bufnum, lnum, col, off, curswant] ~
    if mode() == "v" || mode() == "V" || mode() == "\<C-V>"
        let [line_start, column_start] = getpos("'<")[1:2]
        let [line_end, column_end] = getpos("'>")[1:2]
        let column_end = column_end == 2147483647 ? len(getline(line_end)) : column_end
    else
        let [line_start, column_start] = getcurpos()[1:2]
        let [line_end, column_end] = getcurpos()[1:2]
    endif

    "echom "Quickeval at: ".line_start."::".column_start."::".line_end."::".column_end

    let l:config = {
        \ 'quick_eval': a:quick_eval,
        \ 'buf': nvim_get_current_buf(),
        \ 'query': l:queryPath,
        \ 'db': s:database,
        \ 'startLine': line_start,
        \ 'startColumn': column_start,
        \ 'endLine': line_end,
        \ 'endColumn': column_end,
        \ 'metadata': codeql#extractQueryMetadata(l:queryPath),
        \ }
    let res = luaeval("require('ql.queryserver').run_query(_A)", l:config)

endfunction

" function! s:save_session(file, database, issues, query) abort
"     let l:dbname = split(a:database, '/')[-1:][0]
"     let l:queryfile = fnamemodify(a:query, ':t')
"     call add(s:history, {
"         \ 'file': a:file,
"         \ 'database': l:dbname,
"         \ 'epoch': localtime(),
"         \ 'time': strftime('%c'),
"         \ 'issues': a:issues,
"         \ 'query': l:queryfile
"         \ })
" endfunction

" function! codeql#show_history(element) abort
"     if a:element < len(s:history)
"         let l:version = s:history[a:element]
"         call codeql#show_results(l:version['file'], l:version['database'], l:version['query'], 1)
"     endif
" endfunction

" function! codeql#history() abort
"     "let s:history = filter(s:history, 'isdirectory(v:val.database) && filereadable(v:val.file)')
" 	let l:options = map(copy(s:history), 'v:val.query." (".v:val.issues." results) (".v:val.time.") [".v:val.database."]"')
"     if exists("*fzf#run")
"         call fzf#run(fzf#wrap({
"             \ 'source': map(deepcopy(l:options), {idx, item -> string(idx).'::'.item}),
"             \ 'sink': function('codeql#show_history'),
"             \ 'options': '+m --with-nth 2.. -d "::"',
"             \ }))
"     else
"         let l:option = inputlist(['Select: '] + l:options)
"         call codeql#show_history(l:option-1)
"     endif
" endfunction
