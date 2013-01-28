#!/bin/bash

# Script to benchmark the ruby agent under various versions of ruby in ci.

echo "Executing $0"
echo "Running in $(pwd)"

# print commands in this script as they're invoked
# set -x
# fail if any command fails
set -e

# check for require environment variables
if [ "x$RUBY" == "x" ]; then
  echo '$RUBY is undefined'
  exit 1
fi


. "$HOME/.rvm/scripts/rvm"
rvm use $RUBY || rvm install $RUBY
echo `which ruby`

# make sure that we're in the project root
script_dirname=`dirname $0`
cd "$script_dirname/../../"
pwd

rm -rf tmp
mkdir -p tmp
cd tmp
git clone --depth=1 git@github.com:newrelic/agent_prof.git agent_prof
cd agent_prof

perl -p -i'.bak' -e 's#gem +.newrelic_rpm.*$#gem "newrelic_rpm", :path => "\.\.\/\.\.\/"#' Gemfile

rvm --force gemset delete ruby_bench_$RUBY
rvm gemset create ruby_bench_$RUBY
rvm gemset use ruby_bench_$RUBY

if [ "x$RUBY" == "x1.8.6" ]; then
  # Bundler 1.1 dropped support for ruby 1.8.6
  gem install bundler -v'~>1.0.0' --no-rdoc --no-ri
else
  gem install bundler --no-rdoc --no-ri
fi

bundle
script/run
bundle exec script/post_log_to_dashboard


