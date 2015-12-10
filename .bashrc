VISUAL=vim
EDITOR="$VISUAL"
CLICOLOR=1
export VISUAL EDITOR CLICOLOR

# load aliases
source "$HOME/.aliases"

# Run tmux with TERM set for osx
alias tmux="TERM=screen-256color-bce tmux"

# source chruby
if [ -f '/usr/local/opt/chruby/share/chruby' ]; then
  source /usr/local/opt/chruby/share/chruby/chruby.sh
  source /usr/local/opt/chruby/share/chruby/auto.sh
fi

# source git completion
if [ -f '/usr/local/etc/bash_completion.d/git-completion.bash' ]; then
  source '/usr/local/etc/bash_completion.d/git-completion.bash'
fi

source "$HOME/.dotfile-includes/git-bash-support"

export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;36m\]\w\[\033[00m\]\$(git_prompt_info '(%s)')$ "
