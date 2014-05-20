# config valid only for Capistrano 3.1
lock '3.2.1'

set :application, 'test'

set :newrelic_user, ENV["NEWRELIC_USER"] if ENV["NEWRELIC_USER"]
set :newrelic_appname, ENV["NEWRELIC_APPNAME"] if ENV["NEWRELIC_APPNAME"]
