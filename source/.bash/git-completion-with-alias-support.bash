# This file expects the git-completion extension to be loaded in ~/.bash/git-completion
# and git aliases to be defined in ~/.gitconfig in order to make them play nicely together

# source git completion
source "$HOME/.bash/git-completion.bash"

function_exists() {
    declare -f -F $1 > /dev/null
    return $?
}

for al in `__git_aliases`; do
    alias g$al="git $al"

    complete_func=_git_$(__git_aliased_command $al)
    function_exists $complete_fnc && __git_complete g$al $complete_func
done
