#!/bin/bash
#
# our testing kicks off > 180 travis "builds" so let's use a local gemstash
# mirror for all of our rubygems needs if we are in our internal testing env

set -ev

if [ -n "$TRAVIS_PRIVATE" ]; then
  bundle config mirror.https://rubygems.org http://ci.datanerd.us:9292
fi
