# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

config.cache_classes = false
config.whiny_nils = true
config.action_controller.consider_all_requests_local = true
config.action_view.debug_rjs                         = true
config.action_controller.perform_caching             = false
config.action_mailer.raise_delivery_errors = false
config.gem "mocha", :version => '>= 0.9.5'
if defined? JRuby
config.gem "jdbc-sqlite3", :lib => "sqlite3"
else
config.gem "sqlite3-ruby", :lib => "sqlite3"
end
