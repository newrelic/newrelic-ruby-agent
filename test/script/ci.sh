#!/bin/bash

# Script to run test suites in CI or in development mode.  This script handles
# checking out test dependencies (currently rpm_test_app and it's dependencies)
# and executing them.
#
# It relies on 3 environment variables:
#
# RUBY - The rvm ruby you want to use (e.g. 1.8.7, ree, jruby)
#
# BRANCH - The rpm_test_app branch you want to use (e.g. rails20, rails31)
#
# RPM_TEST_APP_CLONE_URL - where to clone the test app from (e.g.
# git://github.com/newrelic/rpm_test_app.git, /path/in/my/filesystem)
#
# Example usage:
# RPM_TEST_APP_CLONE_URL=git://github.com/newrelic/rpm_test_app.git \
# RUBY=ree BRANCH=rails20 test/script/ci.sh
#
# RPM_TEST_APP_CLONE_URL=git://github.com/newrelic/rpm_test_app.git \
# RUBY=ree BRANCH=rails20 test/script/ci.sh
#
# RPM_TEST_APP_CLONE_URL=~/dev/rpm_test_app/ \
# RUBY=jruby BRANCH=rails22 test/script/ci.sh

echo "Executing $0"
echo "Running in $(pwd)"



# print commands in this script as they're invoked
set -x
# fail if any command fails
set -e

# check for require environment variables
if [ "x$RUBY" == "x" ]; then
  echo '$RUBY is undefined'
  exit 1
fi
if [ "x$BRANCH" == "x" ]; then
  echo '$BRANCH is undefined'
  exit 1
fi
if [ "x$RPM_TEST_APP_CLONE_URL" == "x" ]; then
  echo '$RPM_TEST_APP_CLONE_URL is undefined'
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
echo "cloning rpm test app from $RPM_TEST_APP_CLONE_URL"
git clone --depth=1 $RPM_TEST_APP_CLONE_URL rpm_test_app
echo "done"
cd rpm_test_app
git checkout -t origin/$BRANCH || git checkout $BRANCH
mkdir -p log
mkdir -p tmp
if [ "x$BRANCH" == "xrails20" ]; then
  printf "\e[0;31;49mWarning:\e[0m "
  echo "Testing against the rails20 branch requires your changes to be committed. Uncommitted changes will not be used."
  mkdir -p vendor/plugins
  git clone ../.. vendor/plugins/newrelic_rpm
else
  perl -p -i'.bak' -e 's#gem .newrelic_rpm.*$#gem "newrelic_rpm", :path => "\.\.\/\.\.\/"#' Gemfile
fi

# save time by reusing the gemset if it exists

gemset=ruby_agent_tests_$BRANCH
rvm gemset use $gemset || ( rvm gemset create $gemset && rvm gemset use $gemset )

if [ "x$RUBY" == "x1.8.6" ]; then
  # Bundler 1.1 dropped support for ruby 1.8.6
  gem install bundler -v'~>1.0.0' --no-rdoc --no-ri
else
  gem install bundler --no-rdoc --no-ri
fi


export RAILS_ENV=test
bundle
bundle exec rake --trace db:create:all ci:setup:testunit test:newrelic




