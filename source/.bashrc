VISUAL=vim
EDITOR="$VISUAL"
TERM=xterm-256color
export VISUAL EDITOR TERM

# source chruby
if [ -f '/usr/local/opt/chruby/share/chruby' ]; then
  source /usr/local/opt/chruby/share/chruby/chruby.sh
  source /usr/local/opt/chruby/share/chruby/auto.sh
fi

# source git completion alias support
source "$HOME/.bash/git-completion-with-alias-support.bash"

# source hub completion
source "$HOME/.bash/hub.bash-completion.sh"

# source git support for bash
source "$HOME/.bash/git-prompt.bash"

# load aliases
source "$HOME/.aliases"

export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;36m\]\w\[\033[00m\]\$(git_prompt_info '(%s)')$ "
