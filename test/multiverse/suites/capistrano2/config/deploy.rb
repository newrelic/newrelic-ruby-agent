# encoding: utf-8
# # This file is distributed under New Relic's license terms.
# # See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'bundler/capistrano'

set :application, "new_relic_capistrano"
set :repository,  "~/new_relic_capistrano"
set :current_path, ""
set :newrelic_license_key, "bootstrap_newrelic_admin_license_key_000"
set :newrelic_rails_env, "development"

set :scm, :none

role :web, "localhost"
role :app, "localhost"
role :db,  "localhost"

set :use_sudo, false
