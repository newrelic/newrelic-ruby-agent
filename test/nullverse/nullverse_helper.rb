# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'minitest/autorun'

unless defined?(Minitest::Test)
  Minitest::Test = MiniTest::Unit::TestCase
end

$:.unshift File.expand_path('../../../lib', __FILE__)
