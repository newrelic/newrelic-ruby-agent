# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/instrumentation/action_mailbox_subscriber'

if defined?(ActionMailbox) &&
    ActionMailbox.respond_to?(:gem_version) && # 'require "actionmailbox"' doesn't require version...
    NewRelic::Helper.version_satisfied?(ActionMailbox.gem_version, '>=', '7.1.0.alpha') # notifications added in Rails 7.1
  require_relative 'rails/action_mailbox_subscriber'
else
  puts "Skipping tests in #{File.basename(__FILE__)} because ActionMailbox is unavailable or < 7.1" if ENV['VERBOSE_TEST_OUTPUT']
end
