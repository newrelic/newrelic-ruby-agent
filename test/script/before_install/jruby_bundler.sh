#!/bin/bash
#
# currently there's an incompatibility between Bundler 1.13 with JRuby 1.7, see Bundler issue #4975
# so we revert bundler versions to 1.12.5 on that version
#
# further digging suggests the bundler/jruby problem was actually a jruby bug,
# apparently fixed in 1.7.26. if we upgrade our older jruby testing, which seems
# unlikely at this point, be sure to change this uninstall line to point to the
# correct location.
#
# TODO: remove when older rubies are deprecated, RUBY-1668

set -ev

if [[ `ruby --version` =~ ^jruby\ 1\. ]]; then
  gem uninstall -x -i $HOME/.rvm/gems/jruby-1.7.23@global bundler
  if [ -n "$GEMSTASH_MIRROR" ]; then
    gem install --clear-sources --source $GEMSTASH_MIRROR bundler -v 1.12.5
  else
    gem install bundler -v 1.12.5
  fi
fi
