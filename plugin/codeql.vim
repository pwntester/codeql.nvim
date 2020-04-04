" opts
let g:codeql_mem_opts = []

" commands
command! -nargs=1 -complete=file SetDatabase call codeql#setDatabase(<f-args>)
command! RunQuery call codeql#runQuery(v:false)
command! -range QuickEval call codeql#runQuery(v:true)
command! QLHistory call codeql#history()

" TODO: CreateDB <lang> <source-root> <db>
" TODO: CleanDB

" mappings
nnoremap qr :RunQuery<CR>
nnoremap qe :QuickEval<CR>
vnoremap qe :QuickEval<CR>

command! -range Test call Test()
function! Test() abort
    let cursor = getcurpos()
    let [line_start, column_start] = getpos("'<")[1:2]
    let [line_end, column_end] = getpos("'>")[1:2]
    let column_end = column_end == 2147483647 ? len(getline(line_end)) : column_end
    echom line_start.'::'.column_start.'::'.line_end.'::'.column_end
endfunction
