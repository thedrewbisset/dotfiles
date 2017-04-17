" Load plugins based on detected filetype
filetype plugin indent on

" Use persistent undo
set undodir=$HOME/.vim/undo/
set undofile
set undolevels=1000
set undoreload=10000

" Use shorter delay times
set timeoutlen=1000 " mapping delay
set ttimeoutlen=10  " key code delay
set shell=bash

""" Sensible configs
if has('autocmd')
  filetype plugin indent on
endif
if has('syntax') && !exists('g:syntax_on')
  syntax enable
endif
set autoindent
set complete-=i
set smarttab

set nrformats-=octal

set incsearch

if maparg('<C-L>', 'n') ==# ''
  nnoremap <silent> <C-L> :nohlsearch<C-R>=has('diff')?'<Bar>diffupdate':''<CR><CR><C-L>
endif

set laststatus=2
set ruler
set wildmenu

set autoread

" Allow color schemes to do bright colors without forcing bold.
if &t_Co == 8 && $TERM !~# '^linux\|^Eterm'
  set t_Co=16
endif

""" End sensible config

map <C-j> <C-W>j
map <C-k> <C-W>k
map <C-h> <C-W>h
map <C-l> <C-W>l

" vim tab navigation
nnoremap th :tabfirst<CR>
nnoremap tj :tabprev<CR>
nnoremap tk :tabnext<CR>
nnoremap tl :tablast<CR>
nnoremap tc :tabclose<CR>
nnoremap tn :tabnew<CR>

" disable arrow navigation keys
inoremap  <Up>    <NOP>
inoremap  <Down>  <NOP>
inoremap  <Left>  <NOP>
inoremap  <Right> <NOP>
noremap   <Up>    <NOP>
noremap   <Down>  <NOP>
noremap   <Left>  <NOP>
noremap   <Right> <NOP>

" show line numbers
set number

" use spaces and indent by two
set expandtab tabstop=2 shiftwidth=2

" git commit messages configuration
autocmd Filetype gitcommit setlocal spell textwidth=72
hi diffAdded ctermfg=green
hi diffRemoved ctermfg=red

" Better search behavior
set hlsearch
set incsearch
set ignorecase
set smartcase

" Unhighlight search results
map <Leader><space> :nohl<cr>

" Don't scroll off the edge of the page
set scrolloff=5

" NERDTree configuration
let NERDTreeIgnore=['\~$', 'tmp', '\.git', '\.bundle', '.DS_Store', 'tags', '.swp']
let NERDTreeShowHidden=1
map <Leader>n :NERDTreeToggle<CR>
map <Leader>fnt :NERDTreeFind<CR>

command! -nargs=0 -bar Qargs execute 'args' QuickfixFilenames()
function! QuickfixFilenames()
  " Building a hash ensures we get each buffer only once
  let buffer_numbers = {}
  for quickfix_item in getqflist()
    let buffer_numbers[quickfix_item['bufnr']] = bufname(quickfix_item['bufnr'])
  endfor
  return join(map(values(buffer_numbers), 'fnameescape(v:val)'))
endfunction
