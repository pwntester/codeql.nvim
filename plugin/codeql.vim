" opts
let g:codeql_mem_opts = []
let g:codeql_panel_longnames = v:false
let g:codeql_panel_filename = v:true
let g:codeql_group_by_sink = v:true


" commands
command! -nargs=1 -complete=file SetDatabase lua require('ql.main').set_database(<f-args>)
command! RunQuery lua require('ql.main').run_query(false)
command! -range QuickEval lua require('ql.main').run_query(true)

" mappings
autocmd FileType ql nnoremap qr :RunQuery<CR>
autocmd FileType ql nnoremap qe :QuickEval<CR>
autocmd FileType ql vnoremap qe :QuickEval<CR>

" TODO: CreateDB <lang> <source-root> <db>
" TODO: CleanDB
" TODO: RestartQueryServer
" TODO: History
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
