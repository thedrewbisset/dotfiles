#!/bin/bash
export HISTSIZE=10000

# always append history
shopt -s histappend

# immediately record history
PROMPT_COMMAND='history -a'

export HISTIGNORE='cd*:ls*:ll*:lla*:mv*:rm*:touch*:history:man*:which*:cat*:less*:ps*:bundle install*:npm install*:brew install*:rbenv install*:exit:clear:irb:nix-env --install*'

export HISTCONTROL=ignorespace:ignoredups
