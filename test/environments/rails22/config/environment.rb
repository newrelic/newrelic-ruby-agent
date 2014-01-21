# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# Specifies gem version of Rails to use when vendor/rails is not present
RAILS_GEM_VERSION = '2.2.3'

# Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')

GC.enable_stats if GC.respond_to?(:enable_stats)

Rails::Initializer.run do |config|
  config.time_zone = 'UTC'
  if defined?(JRuby)
    gem 'activerecord-jdbcmysql-adapter'
  end

  config.action_controller.session = {
    :session_key => '_rails22blog_session',
    :secret      => '603603ece6f4792a7a1284a903788646998ad4646ed19d5f06e2af7578660b7b39e54c685f3efa245084eaa5447684a0d8afc96742b63f0e133e8587272c71d1'
  }
end

require 'application'
