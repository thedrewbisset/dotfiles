source $HOME/.profile
source $HOME/.bashrc

eval "$(rbenv init -)"
eval "$(hub alias -s)"

# Use brew's sqlite
export PATH="/usr/local/opt/sqlite/bin:$PATH"

# Use bats
export PATH="~/dev/bats/bin:$PATH"

# Use brew's python3
export PATH="/usr/local/opt/python/libexec/bin:$PATH"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/drewbisset/dev/google-cloud-sdk/path.bash.inc' ]; then source '/Users/drewbisset/dev/google-cloud-sdk/path.bash.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/drewbisset/dev/google-cloud-sdk/completion.bash.inc' ]; then source '/Users/drewbisset/dev/google-cloud-sdk/completion.bash.inc'; fi
