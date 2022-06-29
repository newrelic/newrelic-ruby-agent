# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../test_helper'
require 'new_relic/agent/instrumentation/action_view_subscriber'

module NewRelic
  module Agent
    module Instrumentation
      class ActionViewSubscriberTest < Minitest::Test
        defer_testing_to_min_supported_rails __FILE__, 4.0 do
          require_relative 'rails/action_view_subscriber'
        end
      end
    end
  end
end
