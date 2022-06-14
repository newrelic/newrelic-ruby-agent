# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require "net_http_test_cases"
SimpleCov.command_name "test:multiverse[net_http]"

class NetHttpTest < Minitest::Test
  include NetHttpTestCases
end
