if exists('b:current_syntax')
    finish
endif

syntax keyword codeqlKeyword         where select in as order by asc desc module result this super instanceof
syntax keyword codeqlAnnotation      abstract cached external final library noopt private deprecated query pragma language bindingset noinline nomagic monotonicAggregates transient contained
syntax keyword codeqlLogic           not and or implies forall forex any none
syntax keyword codeqlConditional     if then else
syntax keyword codeqlType            int float string boolean date
syntax keyword codeqlAggregate       avg concat count max min rank strictconcat strictcount strictsum sum
syntax keyword codeqlConstant        false true
syntax keyword codeqlImport          import nextgroup=codeqlQualified skipwhite
syntax match   codeqlTypeDecl        '\v\s*class\s+\i+\s*(extends|\{).*' contains=codeqlTypeMod,codeqlTypeName
syntax keyword codeqlTypeMod         class extends contained
syntax match   codeqlTypeName        '\v[a-zA-Z0-9:_]+' contained
syntax match   codeqlConstructor     '\v\s*\i+\(\)\s*\{' contains=codeqlConstructorName
syntax match   codeqlConstructorName '\i' contained
syntax match   codeqlPredicateDecl   '\v(override)?\s*predicate\s+[a-zA-Z0-9_]+\s*\(\ze.*' contains=codeqlPredicateMod,codeqlPredicateName
syntax keyword codeqlPredicateMod    override predicate contained
syntax match   codeqlPredicateName   '\i' contained
syntax region  codeqlVarDecl1        start=/\v\s*exists\(/ end=/|/ keepend contains=codeqlVarDeclMod,codeqlVarDeclType
syntax region  codeqlVarDecl2        start=/\v\s*from\s+/ end=/where/ end=/select/ keepend contains=codeqlVarDeclMod,codeqlVarDeclType
syntax keyword codeqlVarDeclMod      exists from select where contained
syntax match   codeqlVarDeclType     '\l\@<!\<\u[a-zA-Z:_]\+' contained
syntax region  codeqlString          start=/\v"/ skip=/\v\\./ end=/\v"/
syntax match   codeqlInt             "\s\+\d\+"
syntax match   codeqlFloat           "\s\+\d\+\.\d\+"
syntax match   codeqlComparison      "[!=<>*]"
syntax region  codeqlComment         start="/\*" end="\*/" contains=@Spell
syntax match   codeqlComment         "//.*$" contains=@Spell

let b:current_syntax = "codeql"

highlight default link codeqlComparison    Operator
highlight default link codeqlLogic         Keyword
highlight default link codeqlAggregate     Keyword
highlight default link codeqlConditional   Conditional
highlight default link codeqlType          Type
highlight default link codeqlConstant      Constant
highlight default link codeqlImport        Include
highlight default link codeqlKeyword       Keyword
highlight default link codeqlAnnotation    PreProc
highlight default link codeqlTypeMod       Keyword 
highlight default link codeqlTypeName      Function
highlight default link codeqlConstructorName Function
highlight default link codeqlPredicateMod  Keyword 
highlight default link codeqlPredicateName Function
highlight default link codeqlVarDeclMod    Keyword 
highlight default link codeqlVarDeclType   Function
highlight default link codeqlString        String
highlight default link codeqlInt           Number
highlight default link codeqlFloat         Float
highlight default link codeqlComment       Comment
