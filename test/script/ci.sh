#!/bin/bash
set -e

unset MERB_ENV
unset RUBY_ENV
unset RACK_ENV
unset RAILS_ENV

if [ "$TYPE" = "UNIT" ]; then
  bundle exec rake test:env[$ENVIRONMENT]
elif [ "$TYPE" = "FUNCTIONAL" ]; then
  bundle exec rake test:multiverse[group=$GROUP,verbose,nocache]
elif [ "$TYPE" = "NULLVERSE" ]; then
  bundle exec rake test:nullverse
fi
