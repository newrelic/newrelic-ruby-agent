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
  include SidekiqTestHelpers

  # def test_running_a_job_produces_a_healthy_segment
  #   # NOTE: run_job itself asserts that exactly 1 segment could be found
  #   segment = run_job

  #   assert_predicate segment, :finished?
  #   assert_predicate segment, :record_metrics?
  #   assert segment.duration.is_a?(Float)
  #   assert segment.start_time.is_a?(Float)
  #   assert segment.end_time.is_a?(Float)
  #   assert segment.time_range.is_a?(Range)
  # end

  # Sidekiq::Job::Setter#perform_inline is expected to light up all registered
  # client and server middleware, and the lighting up of NR's server middleware
  # will produce a segment
  # def test_works_with_perform_inline
  #   # Sidekiq version 6.4.2 ends up invoking String#constantize, which is only
  #   # delivered by ActiveSupport, which this test suite doesn't currently
  #   # include.
  #   skip 'This test requires Sidekiq v7+' unless Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new('7.0.0')

  #   in_transaction do |txn|
  #     NRDeadEndJob.perform_inline
  #     segments = txn.segments.select { |s| s.name.eql?('Nested/OtherTransaction/SidekiqJob/NRDeadEndJob/perform') }

  #     assert_equal 1, segments.size, "Expected to find a single Sidekiq job segment, found #{segments.size}"
  #   end
  # end

  def test_delay_extension
    skip 'This test requires Sidekiq v7+' unless Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new('7.0.0')

    

    in_transaction do |txn|
      NRDeadEndJob.delay_until(Time.now).do_something
      segments = txn.segments.select { |s| s.name.eql?('Nested/OtherTransaction/SidekiqJob/NRDeadEndJob/perform') }

      assert_equal 1, segments.size, "Expected to find a single Sidekiq job segment, found #{segments.size}"
    end
  end
end
