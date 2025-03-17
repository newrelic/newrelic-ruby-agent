# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'sidekiq_test_helpers'
require "sidekiq/delay_extensions/testing"

Sidekiq::DelayExtensions.enable_delay!


module Sidekiq::Extensions
end
Sidekiq::Extensions::DelayedClass = Sidekiq::DelayExtensions::DelayedClass


class SidekiqInstrumentationTest < Minitest::Test

  def test_delay_extension
    skip 'This test requires Sidekiq v7+' unless Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new('7.0.0')

    in_transaction do |txn|
      Dolce.delay.long_method
      # binding.irb
      segments = txn.segments.select { |s| s.name.eql?('Nested/OtherTransaction/SidekiqJob/Dolce/long_method') }

      assert_equal 1, segments.size, "Expected to find a single Sidekiq job segment, found #{segments.size}"
    end
  end
end
