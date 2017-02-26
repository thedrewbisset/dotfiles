runtime! autoload/pathogen.vim
if exists('g:loaded_pathogen')
  execute pathogen#infect('~/.vimbundles/{}')
endif

filetype plugin indent on


set shell=bash

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

" git commit messages get 50/72 vertical bars
autocmd BufNewFile,BufRead COMMIT_EDITMSG set colorcolumn=50,72

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
