#!/bin/bash
#
# travis caching for Gemfile.lock files
#
# we have many Gemfiles throughout the test/ tree, including some that are
# generated during the testing process. these can be used for bundling:
#     * at the onset of the test (ex: rake test:env[norails])
#     * at various steps in the process
#       (ex: rake test:multiverse[group=background])
#
# each bundle requires many rubygems.org hits, as well as installs for each
# gem version. by caching the Gemfile.lock files, and copying them in to the
# tree at the correct places, we can skip lock file generation step and go
# straight to installing the specific gem versions.

set -ev

mkdir -p /home/travis/gemfiles
touch /home/travis/gemfiles/IGNORE.txt
cp -R /home/travis/gemfiles/* .
