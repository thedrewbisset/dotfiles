VISUAL=vim
EDITOR="$VISUAL"
CLICOLOR=1
export VISUAL EDITOR CLICOLOR

# source chruby
if [ -f '/usr/local/opt/chruby/share/chruby' ]; then
  source /usr/local/opt/chruby/share/chruby/chruby.sh
  source /usr/local/opt/chruby/share/chruby/auto.sh
fi

# source git completion
if [ -f '/usr/local/etc/bash_completion.d/git-completion.bash' ]; then
  source '/usr/local/etc/bash_completion.d/git-completion.bash'
fi
