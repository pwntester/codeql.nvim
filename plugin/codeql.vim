" plugin options
if !exists('g:codeql_search_path')
    let g:codeql_search_path = '/Users/pwntester/codeql-home/codeql-repo'
endif

" commands
command! -nargs=* -complete=file RunQuery call codeql#runQuery(<f-args>)
command! QLHistory call codeql#history()

" TODO: CreateDB <lang> <source-root> <db>
" TODO: CleanDB
