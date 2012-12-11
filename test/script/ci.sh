#!/bin/bash

# Script to run test suites in CI or in development mode.  This script handles
# checking out test dependencies (currently rpm_test_app and its dependencies)
# and executing them.
#
# It relies on 2 environment variables:
#
# RUBY - The rbenv ruby you want to use (e.g. 1.8.7, ree, jruby)
#
# BRANCH - The rpm_test_app branch you want to use (e.g. rails20, rails31)
#
# Example usage:
# RUBY=ree BRANCH=rails20 test/script/ci.sh
#
# RUBY=ree BRANCH=rails20 test/script/ci.sh
#
# RUBY=jruby BRANCH=rails22 test/script/ci.sh

echo "Executing $0"
echo "Running in $(pwd)"

# print commands in this script as they're invoked
#set -x
# fail if any command fails
set -e

# check for require environment variables
if [ "x$RUBY" == "x" ]; then
  echo '$RUBY is undefined'
  echo 'defaulting to 1.9.3'
  export RUBY=1.9.3-p286
fi
if [ "x$BRANCH" == "x" ]; then
  echo '$BRANCH is undefined'
  echo 'defaulting to rails31'
  export BRANCH=rails31
fi

if [ "x$JOB_NAME" == "x" ]; then
  echo '$JOB_NAME is undefined'
  echo 'defaulting to clrun'
  export PROJECT_NAME=clrun
else
  CLEANSED_NAME=`echo $JOB_NAME  | sed "s/label//" | sed "s/Portland//" | sed "s/BRANCH//" | sed "s/RUBY//" | sed "s/[=\/,\._]//g" | sed "s/ReleaseCandidate/RC/"`
  echo "setting PROJECT_NAME to $CLEANSED_NAME"
  export PROJECT_NAME="$CLEANSED_NAME"
fi

eval "$(rbenv init -)" || true
rbenv shell $RUBY
if [ "x$(rbenv version-name)" = "x$RUBY" ]; then
  echo "switched to ruby $RUBY"
else
  rbenv install $RUBY
  rbenv shell $RUBY
  if [ "x$(rbenv version-name)" = "x$RUBY" ]; then
    echo "switched to ruby $RUBY"
  else
    echo "failed to install ruby $RUBY"
    exit 1
  fi
fi

echo `which ruby`
ruby -v

rake -h > /dev/null || gem install rake

echo "generating gemspec"
rake gemspec


# make sure that we're in the project root
script_dirname=`dirname $0`
cd "$script_dirname/../../"
pwd

rm -rf tmp
mkdir -p tmp
cd tmp


#rpm_test_app_cache=~/.rpm_test_app_cache
rpm_test_app_cache=~/workspace/.rpm_test_app_cache
(
  echo "updating local cache of rpm_test_app in $rpm_test_app_cache"
  git clone --mirror git://github.com/newrelic/rpm_test_app.git $rpm_test_app_cache || true
  cd $rpm_test_app_cache
)

git clone $rpm_test_app_cache rpm_test_app
cd rpm_test_app

git checkout -t origin/$BRANCH || git checkout $BRANCH


# Re-write database.yml to this here doc
( cat << "YAML" ) > config/database.yml
# Shared properties for mysql db
mysql: &mysql
  adapter: mysql
  socket: <%= (`uname -s` =~ /Linux/ ) ? "" :"/tmp/mysql.sock" %>
  username: root
  host: localhost
  database: <%= ENV['PROJECT_NAME'] %>

# Shared properties for postgres.  This won't work with our schema but
# Does work with agent tests
sqlite3: &sqlite3
<% if defined?(JRuby) %>
  adapter: jdbcsqlite3
<% else %>
  adapter: sqlite3
<% end %>
  database: db/all.sqlite3
  pool: 5
  timeout: 5000
  host: localhost

# SQLite version 3.x
#   gem install sqlite3-ruby (not necessary on OS X Leopard)
development:
  <<: *sqlite3

test:
  <<: *mysql

production:
  <<: *mysql
YAML


mkdir -p log
mkdir -p tmp
if [ "x$BRANCH" == "xrails20" ]; then
  echo "Warning: Rails 2.0 support in progress. This probably only works in CI"
  mkdir -p vendor/plugins
  GEM=`ls ../../../*.gem | tail -n1`
  (cd vendor/plugins && gem unpack ../../$GEM)
  mv vendor/plugins/newrelic_rpm* vendor/plugins/newrelic_rpm
else
  perl -p -i'.bak' -e 's#gem .newrelic_rpm.*$#gem "newrelic_rpm", :path => "\.\.\/\.\.\/"#' Gemfile
fi

if [ "x$RUBY" == "x1.8.6" ]; then
  # Bundler 0.1 dropped support for ruby 1.8.6
  bundle -h > /dev/null || gem install bundler -v'~>1.0.0' --no-rdoc --no-ri
else
  bundle -h > /dev/null || gem install bundler --no-rdoc --no-ri
fi


export RAILS_ENV=test
bundle --local || bundle

# FIXME:  Here we actually trigger the tests. Since the agent deals so heavily
# in units of time we have many tests that assert that durations are measured
# correctly.  These almost always pass, but as the CI machine has come under
# heavier load there tend to be discrepencies between the duration measured in
# the test and the duration the agent measures.  This is due to lags in CPU
# scheduling since many processes are running on the box simultaneously.
# To reduce the noise from these sporardic failures we rerun the test suite if
# there are failures to see if they are transient (instead of re-running it by
# hand).  Ultimately we'll move towards a more elegant solution.

bundle exec rake --trace db:create:all test:newrelic || bundle exec rake --trace test:newrelic
