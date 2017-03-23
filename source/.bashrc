VISUAL=vim
EDITOR="$VISUAL"
TERM=xterm-256color
export VISUAL EDITOR TERM

# load aliases
source "$HOME/.aliases"

# source chruby
if [ -f '/usr/local/opt/chruby/share/chruby' ]; then
  source /usr/local/opt/chruby/share/chruby/chruby.sh
  source /usr/local/opt/chruby/share/chruby/auto.sh
fi

# source git completion
if [ -f '/usr/local/etc/bash_completion.d/git-completion.bash' ]; then
  source '/usr/local/etc/bash_completion.d/git-completion.bash'
fi

# source git support for bash
source "$HOME/.bash/git-support"

export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;36m\]\w\[\033[00m\]\$(git_prompt_info '(%s)')$ "
