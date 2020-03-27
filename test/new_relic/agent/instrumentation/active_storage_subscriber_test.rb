# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__
require 'new_relic/agent/instrumentation/active_storage_subscriber'

def supported_active_storage_available?
  defined?(::ActiveStorage)
end

if supported_active_storage_available?
  require_relative 'rails/active_storage_subscriber'

else
  puts "Skipping tests in #{__FILE__} because ActiveStorage is unavailable"
end

