if exists('b:current_syntax')
    finish
endif

syntax match CodeqlTestPanelKeyword                 '^\zs\(Running\):\ze.*'

highlight default link CodeqlTestPanelKeyword       Keyword

let b:current_syntax = "codeqltestpanel"


