" commands
command! -nargs=* -complete=file RunQuery call codeql#runQuery(<f-args>)
command! QLHistory call codeql#history()

" TODO: CreateDB <lang> <source-root> <db>
" TODO: CleanDB
