# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'
require 'active_record/base'

Bundler.require(:default, Rails.env) if defined?(Bundler)

# TODO: this fixes an issue with Rails 6.0 that is not present with the latest
#       release of 6.1. remove this fix either once we stop testing Rails 6.0
#       with JRuby or once the 6.1 fix is backported to 6.0
require_relative 'psych4_monkeypatch' if defined?(JRuby)

module RpmTestApp
  class Application < Rails::Application
    config.encoding = 'utf-8'
    config.filter_parameters += [:password]
    config.secret_key_base = '414fd9af0cc192729b2b6bffe9e7077c9ac8eed5cbb74c8c4cd628906b716770598a2b7e1f328052753a4df72e559969dc05b408de73ce040c93cac7c51a348e'
    config.eager_load = false
  end
end
