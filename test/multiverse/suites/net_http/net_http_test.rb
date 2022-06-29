# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

SimpleCovHelper.command_name "test:multiverse[net_http]"
require "net_http_test_cases"

class NetHttpTest < Minitest::Test
  include NetHttpTestCases
end
