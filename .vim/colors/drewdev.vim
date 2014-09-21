" Vim color file
" Adapted from Code School theme (http://astonj.com)

set background=dark
highlight clear

if exists("syntax_on")
  syntax reset
endif

let g:colors_name = "DrewDev"

hi Cursor ctermfg=16 ctermbg=145 cterm=NONE
hi Visual ctermfg=NONE ctermbg=59 cterm=NONE
hi CursorLine ctermfg=NONE ctermbg=23 cterm=NONE
hi CursorColumn ctermfg=NONE ctermbg=23 cterm=NONE
hi ColorColumn ctermfg=NONE ctermbg=23 cterm=NONE
hi LineNr ctermfg=241 ctermbg=NONE cterm=NONE
hi VertSplit ctermfg=59 ctermbg=59 cterm=NONE
hi MatchParen ctermfg=180 ctermbg=NONE cterm=NONE
hi StatusLine ctermfg=231 ctermbg=59 cterm=bold
hi StatusLineNC ctermfg=231 ctermbg=59 cterm=NONE
hi Pmenu ctermfg=153 ctermbg=NONE cterm=NONE
hi PmenuSel ctermfg=NONE ctermbg=59 cterm=NONE
hi IncSearch ctermfg=16 ctermbg=107 cterm=NONE
hi Search ctermfg=16 ctermbg=107 cterm=underline
hi Directory ctermfg=68 ctermbg=NONE cterm=NONE
hi Folded ctermfg=247 ctermbg=16 cterm=NONE

hi Normal ctermfg=231 ctermbg=16 cterm=NONE
hi Boolean ctermfg=68 ctermbg=NONE cterm=NONE
hi Character ctermfg=68 ctermbg=NONE cterm=NONE
hi Comment ctermfg=247 ctermbg=NONE cterm=NONE
hi Conditional ctermfg=180 ctermbg=NONE cterm=NONE
hi Constant ctermfg=68 ctermbg=NONE cterm=NONE
hi Define ctermfg=180 ctermbg=NONE cterm=NONE
hi DiffAdd ctermfg=231 ctermbg=64 cterm=bold
hi DiffDelete ctermfg=88 ctermbg=NONE cterm=NONE
hi DiffChange ctermfg=231 ctermbg=23 cterm=NONE
hi DiffText ctermfg=231 ctermbg=24 cterm=bold
hi ErrorMsg ctermfg=NONE ctermbg=NONE cterm=NONE
hi WarningMsg ctermfg=NONE ctermbg=NONE cterm=NONE
hi Float ctermfg=68 ctermbg=NONE cterm=NONE
hi Function ctermfg=153 ctermbg=NONE cterm=NONE
hi Identifier ctermfg=113 ctermbg=NONE cterm=NONE
hi Keyword ctermfg=180 ctermbg=NONE cterm=NONE
hi Label ctermfg=107 ctermbg=NONE cterm=NONE
hi NonText ctermfg=NONE ctermbg=NONE cterm=NONE
hi Number ctermfg=68 ctermbg=NONE cterm=NONE
hi Operator ctermfg=180 ctermbg=NONE cterm=NONE
hi PreProc ctermfg=180 ctermbg=NONE cterm=NONE
hi Special ctermfg=231 ctermbg=NONE cterm=NONE
hi SpecialKey ctermfg=59 ctermbg=23 cterm=NONE
hi Statement ctermfg=180 ctermbg=NONE cterm=NONE
hi StorageClass ctermfg=113 ctermbg=NONE cterm=NONE
hi String ctermfg=107 ctermbg=NONE cterm=NONE
hi Tag ctermfg=153 ctermbg=NONE cterm=NONE
hi Title ctermfg=231 ctermbg=NONE cterm=bold
hi Todo ctermfg=247 ctermbg=NONE cterm=inverse,bold
hi Type ctermfg=153 ctermbg=NONE cterm=NONE
hi Underlined ctermfg=NONE ctermbg=NONE cterm=underline
hi rubyClass ctermfg=180 ctermbg=NONE cterm=NONE
hi rubyFunction ctermfg=153 ctermbg=NONE cterm=NONE
hi rubyInterpolationDelimiter ctermfg=NONE ctermbg=NONE cterm=NONE
hi rubySymbol ctermfg=68 ctermbg=NONE cterm=NONE
hi rubyConstant ctermfg=146 ctermbg=NONE cterm=NONE
hi rubyStringDelimiter ctermfg=107 ctermbg=NONE cterm=NONE
hi rubyBlockParameter ctermfg=74 ctermbg=NONE cterm=NONE
hi rubyInstanceVariable ctermfg=74 ctermbg=NONE cterm=NONE
hi rubyInclude ctermfg=180 ctermbg=NONE cterm=NONE
hi rubyGlobalVariable ctermfg=74 ctermbg=NONE cterm=NONE
hi rubyRegexp ctermfg=179 ctermbg=NONE cterm=NONE
hi rubyRegexpDelimiter ctermfg=179 ctermbg=NONE cterm=NONE
hi rubyEscape ctermfg=68 ctermbg=NONE cterm=NONE
hi rubyControl ctermfg=180 ctermbg=NONE cterm=NONE
hi rubyClassVariable ctermfg=74 ctermbg=NONE cterm=NONE
hi rubyOperator ctermfg=180 ctermbg=NONE cterm=NONE
hi rubyException ctermfg=180 ctermbg=NONE cterm=NONE
hi rubyPseudoVariable ctermfg=74 ctermbg=NONE cterm=NONE
hi rubyRailsUserClass ctermfg=146 ctermbg=NONE cterm=NONE
hi rubyRailsARAssociationMethod ctermfg=186 ctermbg=NONE cterm=NONE
hi rubyRailsARMethod ctermfg=186 ctermbg=NONE cterm=NONE
hi rubyRailsRenderMethod ctermfg=186 ctermbg=NONE cterm=NONE
hi rubyRailsMethod ctermfg=186 ctermbg=NONE cterm=NONE
hi erubyDelimiter ctermfg=NONE ctermbg=NONE cterm=NONE
hi erubyComment ctermfg=247 ctermbg=NONE cterm=NONE
hi erubyRailsMethod ctermfg=186 ctermbg=NONE cterm=NONE
hi htmlTag ctermfg=111 ctermbg=NONE cterm=NONE
hi htmlEndTag ctermfg=111 ctermbg=NONE cterm=NONE
hi htmlTagName ctermfg=111 ctermbg=NONE cterm=NONE
hi htmlArg ctermfg=111 ctermbg=NONE cterm=NONE
hi htmlSpecialChar ctermfg=68 ctermbg=NONE cterm=NONE
hi javaScriptFunction ctermfg=113 ctermbg=NONE cterm=NONE
hi javaScriptRailsFunction ctermfg=186 ctermbg=NONE cterm=NONE
hi javaScriptBraces ctermfg=NONE ctermbg=NONE cterm=NONE
hi yamlKey ctermfg=153 ctermbg=NONE cterm=NONE
hi yamlAnchor ctermfg=74 ctermbg=NONE cterm=NONE
hi yamlAlias ctermfg=74 ctermbg=NONE cterm=NONE
hi yamlDocumentHeader ctermfg=107 ctermbg=NONE cterm=NONE
hi cssURL ctermfg=74 ctermbg=NONE cterm=NONE
hi cssFunctionName ctermfg=186 ctermbg=NONE cterm=NONE
hi cssColor ctermfg=68 ctermbg=NONE cterm=NONE
hi cssPseudoClassId ctermfg=153 ctermbg=NONE cterm=NONE
hi cssClassName ctermfg=153 ctermbg=NONE cterm=NONE
hi cssValueLength ctermfg=68 ctermbg=NONE cterm=NONE
hi cssCommonAttr ctermfg=151 ctermbg=NONE cterm=NONE
hi cssBraces ctermfg=NONE ctermbg=NONE cterm=NONE
