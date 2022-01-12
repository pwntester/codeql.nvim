if exists('b:current_syntax')
  finish
endif

syn match CodeqlNodeRegion '\[\zs\d\+,\s\d\+\ze\]' contains=CodeqlNodeOp,CodeqlNodeNumber
syn match CodeqlNodeType '\[\zs[a-zA-Z_]\+\ze\]'
syn match CodeqlNodeNumber "\d\+" contained
syn match CodeqlNodeOp "[,\-\)]\+" contained

hi def link CodeqlNodeType Identifier
hi def link CodeqlNodeNumber Number
hi def link CodeqlNodeOp Operator

let b:current_syntax = 'codeql_ast'
