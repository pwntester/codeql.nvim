" let s:history = []
"
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
