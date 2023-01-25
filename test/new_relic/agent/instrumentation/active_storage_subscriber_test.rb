# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/instrumentation/active_storage_subscriber'

def supported_active_storage_available?
  defined?(ActiveStorage)
end

if supported_active_storage_available?
  require_relative 'rails/active_storage_subscriber'

else
  puts "Skipping tests in #{File.basename(__FILE__)} because ActiveStorage is unavailable" unless ENV["MIN_TEST_OUTPUT"]
end
