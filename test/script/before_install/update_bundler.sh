#!/bin/bash
#
# ruby-1.9.3 travis has bundler 1.7.6 installed, which pulls in dm-types-1.2.0
# during the datamapper multiverse suite. this causes a dep conflict on json
# gem. updating bundler to latest on that version pulls in dm-types-1.2.2
# and does not cause a conflict.

set -ev

if [[ `ruby --version` =~ ^ruby\ 1\.9\.3 ]]; then
  gem install bundler
fi
