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
