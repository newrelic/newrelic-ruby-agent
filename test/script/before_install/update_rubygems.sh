#!/bin/bash

# Some Ruby and RubyGems versions are incompatible:
#
# * RubyGems 3.x won't install on Ruby 2.2 or older
# * RubyGems 2.x fails our no-warnings check on Ruby 2.6 or later

set -ev

gem update --system || (gem i rubygems-update -v '<3' && update_rubygems)
