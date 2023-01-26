# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/instrumentation/action_mailer_subscriber'

if defined?(ActiveSupport) &&
    defined?(ActionMailer) &&
    ActionMailer.respond_to?(:gem_version) &&
    ActionMailer.gem_version >= Gem::Version.new('5.0') && RUBY_VERSION > '2.4.0'
  require_relative 'rails/action_mailer_subscriber'
else
  puts "Skipping tests in #{File.basename(__FILE__)} because ActionMailer is unavailable" if ENV["VERBOSE_TEST_OUPUT"]
end
