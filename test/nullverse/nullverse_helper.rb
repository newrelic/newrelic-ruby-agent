# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
require 'minitest/autorun'

Minitest::Test = MiniTest::Unit::TestCase unless defined?(Minitest::Test)

$:.unshift File.expand_path('../../lib', __dir__)
