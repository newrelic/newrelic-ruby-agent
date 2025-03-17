# # This file is distributed under New Relic's license terms.
# # See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# # frozen_string_literal: true

require 'active_record'
require 'sidekiq'
require 'newrelic_rpm'
require_relative 'models/dolce'

Sidekiq::DelayExtensions.enable_delay!
