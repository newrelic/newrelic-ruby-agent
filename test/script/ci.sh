#!/bin/bash
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
rvm $RUBY
echo `which ruby`

# make sure that we're in the project root
script_dirname=`dirname $0`
cd "$script_dirname/../../"
pwd

rm -rf tmp
mkdir -p tmp
cd tmp
git clone --depth=1 $RPM_TEST_APP_CLONE_URL rpm_test_app
cd rpm_test_app
git checkout -t origin/$BRANCH || git checkout $BRANCH
mkdir -p log
mkdir -p tmp
if [ "x$BRANCH" == "xrails20" ]; then
  mkdir -p vendor/plugins
  ln -s ../../../.. vendor/plugins/newrelic_rpm
else
  perl -p -i'.bak' -e 's#gem .newrelic_rpm.*$#gem "newrelic_rpm", :path => "\.\.\/\.\.\/"#' Gemfile
fi

rvm --force gemset delete ruby_agent_tests
rvm gemset create ruby_agent_tests
rvm gemset use ruby_agent_tests

gem install bundler --no-rdoc --no-ri


export RAILS_ENV=test
bundle
bundle exec rake --trace db:create:all ci:setup:testunit test:newrelic




