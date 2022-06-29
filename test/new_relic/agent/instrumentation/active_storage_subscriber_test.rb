# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../test_helper'
require 'new_relic/agent/instrumentation/active_storage_subscriber'

def supported_active_storage_available?
  defined?(::ActiveStorage)
end

if supported_active_storage_available?
  require_relative 'rails/active_storage_subscriber'

else
  puts "Skipping tests in #{__FILE__} because ActiveStorage is unavailable"
end
