#!/bin/bash
set -e

unset MERB_ENV
unset RUBY_ENV
unset RACK_ENV
unset RAILS_ENV

if [ "$TYPE" = "UNIT" ]; then
  bundle _1.17.3_ exec rake test:env[$ENVIRONMENT]
elif [ "$TYPE" = "FUNCTIONAL" ]; then
  bundle _1.17.3_ exec rake test:multiverse[group=$GROUP,verbose,nocache]
elif [ "$TYPE" = "NULLVERSE" ]; then
  bundle _1.17.3_ exec rake test:nullverse
fi
