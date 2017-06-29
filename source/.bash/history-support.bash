#!/bin/bash
export HISTSIZE=10000

# always append history
shopt -s histappend

# immediately record history
PROMPT_COMMAND='history -a'

export HISTIGNORE='cd*:ls*:ll*:lla*:mv*:rm*:touch*:fg::history:man*:which*:cat*:less*:git push*:ps*:bundle exec rails s:bundle exec rails c:bundle install*:bundle exec rake db:migrate:npm install*:brew install*:rbenv install*:kill*:exit:vim*:clear:irb:node:nix-env --install*'

export HISTCONTROL=ignorespace:ignoredups
