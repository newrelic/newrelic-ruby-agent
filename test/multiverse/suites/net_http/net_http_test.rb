# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

SimpleCov.command_name "test:multiverse[net_http]" if RUBY_VERSION >= '2.7.0'
require "net_http_test_cases"

class NetHttpTest < Minitest::Test
  include NetHttpTestCases
end
