source $HOME/.profile
source $HOME/.bashrc

eval "$(rbenv init -)"
eval "$(hub alias -s)"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/drewbisset/Downloads/google-cloud-sdk/path.bash.inc' ]; then source '/Users/drewbisset/Downloads/google-cloud-sdk/path.bash.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/drewbisset/Downloads/google-cloud-sdk/completion.bash.inc' ]; then source '/Users/drewbisset/Downloads/google-cloud-sdk/completion.bash.inc'; fi

# Use brew's sqlite
export PATH="/usr/local/opt/sqlite/bin:$PATH"

# Use bats
export PATH="~/dev/bats/bin:$PATH"
