setlocal commentstring=//%s
setlocal tabstop=2
setlocal softtabstop=2
setlocal shiftwidth=2
if executable('codeql') && exists('g:codeql_fmt_onsave') && g:codeql_fmt_onsave
  autocmd FileType ql autocmd BufWrite <buffer> :%!codeql query format -
endif
