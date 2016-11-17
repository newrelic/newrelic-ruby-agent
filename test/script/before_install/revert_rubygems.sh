#!/bin/bash
#
# revert to older rubygems version for ruby versions prior to 2.0
#
# TODO: remove when older rubies are deprecated, RUBY-1668

set -ev

if [[ `ruby --version` =~ ^ruby\ 1\. ]]; then
  if [ -n "$GEMSTASH_MIRROR" ]; then
    gem update --clear-sources --source $GEMSTASH_MIRROR --system 1.8.25
  else
    gem update --system 1.8.25
  fi
fi
