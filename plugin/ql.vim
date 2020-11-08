if exists('loaded_codeql')
  finish
endif

" opts
if !exists('g:codeql_max_ram') 
  let g:codeql_max_ram = -1
endif
if !exists('g:codeql_panel_longnames')
  let g:codeql_panel_longnames = v:false
endif
if !exists('g:codeql_panel_filename')
  let g:codeql_panel_filename = v:true
endif
if !exists('g:codeql_group_by_sink')
  let g:codeql_group_by_sink = v:false
endif
if !exists('g:codeql_path_max_length')
  let g:codeql_path_max_length = -1
endif
if !exists('g:codeql_search_path')
  let g:codeql_search_path = []
endif
if !exists('g:codeql_fmt_onsave')
  let g:codeql_fmt_onsave = 0
endif

"Error
highlight default link CodeqlAstFocus Substitute 

if executable('codeql')
  " commands
  command! -nargs=1 -complete=file SetDatabase lua require'codeql'.set_database(<f-args>)
  command! RunQuery lua require'codeql'.run_query(false)
  command! -range QuickEval lua require'codeql'.run_query(true)
  command! StopServer lua require'codeql.queryserver'.stop_server()
  command! History lua require'codeql.history'.menu()
  command! PrintAST lua require'codeql'.run_templated_query('printAst')
  command! -nargs=1 -complete=file LoadSarif lua require'codeql.loader'.load_sarif_results(<f-args>)

  " mappings
  autocmd FileType ql nnoremap qr :RunQuery<CR>
  autocmd FileType ql nnoremap qe :QuickEval<CR>
  autocmd FileType ql vnoremap qe :QuickEval<CR>
endif

let loaded_codeql = 1
