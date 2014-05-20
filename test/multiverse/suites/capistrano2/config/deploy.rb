require 'bundler/capistrano'

set :application, "new_relic_capistrano"
set :repository,  "~/new_relic_capistrano"
set :current_path, ""
set :newrelic_license_key, "bootstrap_newrelic_admin_license_key_000"
set :newrelic_rails_env, "development"

set :scm, :none

role :web, "localhost"                          # Your HTTP server, Apache/etc
role :app, "localhost"                          # This may be the same as your `Web` server
role :db,  "localhost"

set :use_sudo, false
