if exists('loaded_codeql')
  finish
endif

let loaded_codeql = 1

" commands
command! -nargs=1 -complete=file SetDatabase lua require('ql.main').set_database(<f-args>)
command! RunQuery lua require('ql.main').run_query(false)
command! -range QuickEval lua require('ql.main').run_query(true)
command! StopServer lua require('ql.queryserver').stop_server()
command! History lua require('ql.history').menu()

" mappings
autocmd FileType ql nnoremap qr :RunQuery<CR>
autocmd FileType ql nnoremap qe :QuickEval<CR>
autocmd FileType ql vnoremap qe :QuickEval<CR>
