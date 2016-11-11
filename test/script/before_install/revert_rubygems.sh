#!/bin/bash
#
# revert to older rubygems version for ruby versions prior to 2.0

set -ev

if [[ `ruby --version` =~ ^ruby\ 1\. ]]; then
  if [ -n "$TRAVIS_PRIVATE" ]; then
    gem update --clear-sources --source http://ci.datanerd.us:9292 --system 1.8.25
  else
    gem update --system 1.8.25
  fi
fi
