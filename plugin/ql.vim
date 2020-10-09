if exists('loaded_codeql')
  finish
endif

let loaded_codeql = 1

" commands
if executable('codeql')
  command! -nargs=1 -complete=file SetDatabase lua require'codeql'.set_database(<f-args>)
  command! RunQuery lua require'codeql'.run_query(false)
  command! -range QuickEval lua require'codeql'.run_query(true)
  command! StopServer lua require'codeql.queryserver'.stop_server()
  command! History lua require'codeql.history'.menu()

  " mappings
  autocmd FileType ql nnoremap qr :RunQuery<CR>
  autocmd FileType ql nnoremap qe :QuickEval<CR>
  autocmd FileType ql vnoremap qe :QuickEval<CR>
endif
