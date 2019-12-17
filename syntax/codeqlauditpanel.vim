if exists('b:current_syntax')
    finish
endif

syntax match CodeqlAuditPanelHelp                          '^".*' contains=CodeqlAuditPanelHelpKey,CodeqlAuditPanelHelpTitle
syntax match CodeqlAuditPanelHelpKey                       '" \zs.*\ze:' contained
syntax match CodeqlAuditPanelHelpTitle                     '" \zs-\+ \w\+ -\+' contained
syntax match CodeqlAuditPanelType                          '\a*\s\zs\[.*\]\ze$'
syntax match CodeqlAuditPanelBracket                       '\[.*\]' contains=CodeqlAuditPanelLabel
syntax match CodeqlAuditPanelLabel                         '[^\[\]]*' contained

highlight default link CodeqlAuditPanelFoldIcon             Title 
highlight default link CodeqlAuditPanelVisitable            MoreMsg 
highlight default link CodeqlAuditPanelNonVisitable         ErrorMsg 
highlight default link CodeqlAuditPanelInfo                 Function
highlight default link CodeqlAuditPanelLabel                Function 
highlight default link CodeqlAuditPanelHelp                 Comment 
highlight default link CodeqlAuditPanelHelpKey              Title 
highlight default link CodeqlAuditPanelHelpTitle            Identifier
highlight default link CodeqlAuditPanelType                 Title
highlight default link CodeqlAuditPanelBracket              String
highlight default link CodeqlAuditPanelFile                 NonText
highlight default link CodeqlAuditPanelSeparator            Function
highlight CodeqlRange guifg=#FF628C gui=bold

let b:current_syntax = "codeqlauditpanel"
