" Vim syntax file for IEEE 1687 IJTAG Instrument Connectivity Language (ICL).
" Scope: syntax highlighting only; no LSP or external runtime is required.

if exists("b:current_syntax")
    finish
endif

syntax case match

" Module structure and declarations.
syntax keyword iclStructure Module EndModule
syntax keyword iclDeclaration Port ScanInPort ScanOutPort ScanInterface
syntax keyword iclDeclaration ScanRegister ScanMux DataRegister DataMux
syntax keyword iclDeclaration LogicSignal Instance Alias Enum

" Parameters, attributes, and common ICL properties.
syntax keyword iclParameter Parameter LocalParameter Attribute
syntax keyword iclProperty AccessLink SelectedBy OneHotScanGroup
syntax keyword iclProperty ScanInSource CaptureSource UpdateSource
syntax keyword iclProperty ResetValue ResetMask
syntax keyword iclProperty ClockPort ResetPort TCKPort TMSPort

" Boolean and four-state logic values.
syntax keyword iclBoolean true false
syntax match iclLogicValue "\<[01xXzZ]\>"

" Numeric literals, including sized and unsized based values.
syntax match iclNumber "\<\d\+\>"
syntax match iclBasedNumber "\<\d\+'[sS]\?[bBoOdDhH][0-9a-fA-F_xXzZ?]\+"
syntax match iclBasedNumber "'[sS]\?[bBoOdDhH][0-9a-fA-F_xXzZ?]\+"

" Highlight the declared name following common declaration keywords.
syntax match iclDeclaredName "\<\%(Module\|ScanInterface\|ScanRegister\|ScanMux\|DataRegister\|DataMux\|LogicSignal\|Instance\|Alias\)\>\s\+\zs[A-Za-z_][A-Za-z0-9_$]*"

" Operators and punctuation.
syntax match iclOperator "[!~&|^=<>+*/%-]\+"
syntax match iclDelimiter "[{}()\[\];,.]"

" Strings and comments. ICL supports C/C++-style comments.
syntax region iclString start=+"+ skip=+\\.+ end=+"+
syntax region iclBlockComment start="/\*" end="\*/" contains=iclTodo
syntax match iclLineComment "//.*$" contains=iclTodo
syntax keyword iclTodo TODO FIXME XXX NOTE contained

highlight default link iclStructure Structure
highlight default link iclDeclaration Keyword
highlight default link iclParameter Type
highlight default link iclProperty Identifier
highlight default link iclBoolean Boolean
highlight default link iclLogicValue Constant
highlight default link iclNumber Number
highlight default link iclBasedNumber Number
highlight default link iclDeclaredName Function
highlight default link iclOperator Operator
highlight default link iclDelimiter Delimiter
highlight default link iclString String
highlight default link iclBlockComment Comment
highlight default link iclLineComment Comment
highlight default link iclTodo Todo

let b:current_syntax = "icl"
