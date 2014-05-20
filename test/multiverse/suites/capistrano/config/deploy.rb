# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

set :application, 'test'

# Since Capistrano 3 doesn't allow settings direct from command-line, add any
# settings we want to conditionally toggle from tests in the following manner.
set :newrelic_user, ENV["NEWRELIC_USER"] if ENV["NEWRELIC_USER"]
set :newrelic_appname, ENV["NEWRELIC_APPNAME"] if ENV["NEWRELIC_APPNAME"]
