" opts
let g:codeql_mem_opts = []

" commands
command! -nargs=1 -complete=file SetDatabase call codeql#setDatabase(<f-args>)
command! RunQuery call codeql#runQuery(v:false)
command! -range QuickEval call codeql#runQuery(v:true)
command! QLHistory call codeql#history()

" mappings
nnoremap qr :RunQuery<CR>
nnoremap qe :QuickEval<CR>
vnoremap qe :QuickEval<CR>

" TODO: CreateDB <lang> <source-root> <db>
" TODO: CleanDB
" TODO: RestartQueryServer

