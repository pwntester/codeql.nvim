if exists('b:current_syntax')
    finish
endif

syntax match CodeqlAuditPanelHelp                          '^".*' contains=CodeqlAuditPanelHelpKey,CodeqlAuditPanelHelpTitle
syntax match CodeqlAuditPanelHelpKey                       '" \zs.*\ze:' contained
syntax match CodeqlAuditPanelHelpTitle                     '" \zs-\+ \w\+ -\+' contained
syntax match CodeqlAuditPanelType                          '\a*\s\zs\[.*\]\ze$'

highlight default link CodeqlAuditPanelFoldIcon             Title 
highlight default link CodeqlAuditPanelVisitable            MoreMsg 
highlight default CodeqlAuditPanelNonVisitable              guifg=#FF0000 
highlight default link CodeqlAuditPanelInfo                 Function
highlight default link CodeqlAuditPanelLabel                Comment
highlight default link CodeqlAuditPanelHelp                 Comment 
highlight default link CodeqlAuditPanelHelpKey              Title 
highlight default link CodeqlAuditPanelHelpTitle            Identifier
highlight default link CodeqlAuditPanelType                 Title

let b:current_syntax = "codeqlauditpanel"
