#!/usr/bin/env bash
source 'bin/lib/tools'

get_bundle() {
  (
  if [ -d "$2" ]; then
    echo "Updating $1's $2"
    cd "$2"
    git pull --rebase
  else
    git clone "git://github.com/$1/$2.git"
  fi
  )
}

# prepare build directory
echo $PWD
source_path="$PWD/.vimbundles"

mkdir $source_path

# create symlinks
link $source_path "$HOME/.vimbundles"

cd $source_path

# Tab completion
get_bundle ervandew supertab

# Delimeter defined tabular alignment
get_bundle godlygeek tabular

# Language Tools
# Ruby
get_bundle vim-ruby vim-ruby
get_bundle nelstrom vim-textobj-rubyblock
get_bundle tpope vim-rails
get_bundle tpope vim-cucumber
get_bundle tpope vim-bundler

# JavaScript/CoffeeScript/Clientside
get_bundle kchmck vim-coffee-script
get_bundle leshill vim-json
get_bundle pangloss vim-javascript
get_bundle mustache vim-mustache-handlebars

# Utils
get_bundle mileszs ack.vim
get_bundle tpope vim-abolish
get_bundle tpope vim-commentary
get_bundle tpope vim-endwise
get_bundle tpope vim-eunuch
get_bundle tpope vim-fugitive
get_bundle tpope vim-git
get_bundle tpope vim-haml
get_bundle tpope vim-markdown
get_bundle tpope vim-pathogen
get_bundle tpope vim-rake
get_bundle tpope vim-ragtag
get_bundle tpope vim-repeat
get_bundle tpope vim-rsi
get_bundle tpope vim-sensible
get_bundle tpope vim-speeddating
get_bundle tpope vim-surround
get_bundle tpope vim-unimpaired
get_bundle tpope vim-vividchalk
get_bundle vim-scripts bufkill.vim
get_bundle vim-scripts bufexplorer.zip
get_bundle jgdavey vim-blockle
get_bundle jgdavey vim-railscasts
get_bundle jgdavey tslime.vim
get_bundle jgdavey vim-turbux
get_bundle jgdavey vim-weefactor
get_bundle gregsexton gitv
get_bundle rondale-sc vim-spacejam
get_bundle heartsentwined vim-emblem
get_bundle tpope vim-dispatch
get_bundle milkypostman vim-togglelist
get_bundle christoomey vim-tmux-navigator
get_bundle scrooloose syntastic
get_bundle vim-scripts IndexedSearch
get_bundle goldfeld vim-seek
get_bundle kana vim-textobj-user
get_bundle Rykka lastbuf.vim
get_bundle altercation vim-colors-solarized
get_bundle kien ctrlp.vim
get_bundle scrooloose nerdtree
get_bundle bling vim-airline

vim -c 'call pathogen#helptags()|q'
