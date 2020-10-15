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

