if exists('b:current_syntax')
    finish
endif

syntax match CodeqlPanelHelp                          '^".*' contains=CodeqlPanelHelpKey,CodeqlPanelHelpTitle
syntax match CodeqlPanelHelpKey                       '" \zs.*\ze:' contained
syntax match CodeqlPanelHelpTitle                     '" \zs-\+ \w\+ -\+' contained
syntax match CodeqlPanelType                          '\a*\s\zs\[.*\]\ze$'
syntax match CodeqlPanelBracket                       '\[.*\]' contains=CodeqlPanelLabel
syntax match CodeqlPanelLabel                         '[^\[\]]*' contained

highlight default link CodeqlPanelFoldIcon             Function 
highlight default link CodeqlPanelVisitable            MoreMsg 
highlight default link CodeqlPanelNonVisitable         WarningMsg 
highlight default link CodeqlPanelInfo                 Function
highlight default link CodeqlPanelLabel                Function 
highlight default link CodeqlPanelHelp                 Comment 
highlight default link CodeqlPanelHelpKey              Title 
highlight default link CodeqlPanelHelpTitle            Identifier
highlight default link CodeqlPanelType                 Title
highlight default link CodeqlPanelBracket              String
highlight default link CodeqlPanelFile                 NonText
highlight default link CodeqlPanelSeparator            Function
highlight CodeqlRange guifg=#FF628C gui=bold

let b:current_syntax = "codeqlpanel"
