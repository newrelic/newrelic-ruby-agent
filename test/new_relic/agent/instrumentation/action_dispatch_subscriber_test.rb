# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/instrumentation/action_dispatch_subscriber'

if defined?(ActiveSupport) &&
    defined?(ActionDispatch) &&
    defined?(ActionPack) &&
    ActionPack.respond_to?(:gem_version) &&
    ActionPack.gem_version >= Gem::Version.new('6.0.0') # notifications for dispatch added in Rails 6
  require_relative 'rails/action_dispatch_subscriber'
else
  puts "Skipping tests in #{File.basename(__FILE__)} because ActionDispatch is unavailable or < 6.0" if ENV["VERBOSE_TEST_OUPUT"]
end
