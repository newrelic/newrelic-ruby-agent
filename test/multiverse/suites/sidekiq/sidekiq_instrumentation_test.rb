# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'sidekiq_test_helpers'

class SidekiqInstrumentationTest < Minitest::Test
  include SidekiqTestHelpers

  def test_running_a_job_produces_a_healthy_segment
    # NOTE: run_job itself asserts that exactly 1 segment could be found
    segment = run_job

    assert_predicate segment, :finished?
    assert_predicate segment, :record_metrics?
    assert segment.duration.is_a?(Float)
    assert segment.start_time.is_a?(Float)
    assert segment.end_time.is_a?(Float)
    assert segment.time_range.is_a?(Range)
  end

  def test_disributed_tracing_for_sidekiq
    with_config('distributed_tracing.enabled': true,
      account_id: '190',
      primary_application_id: '46954',
      trusted_account_key: 'trust_this!') do
      NewRelic::Agent.agent.stub :connected?, true do
        run_job

        assert_metrics_recorded 'Supportability/DistributedTrace/CreatePayload/Success'
      end
    end
  end

  def test_captures_errors_taking_place_during_the_processing_of_a_job
    # TODO: MAJOR VERSION - remove this when Sidekiq v5 is no longer supported
    skip 'Test requires Sidekiq v6+' unless Sidekiq::VERSION.split('.').first.to_i >= 6

    segment = run_job('raise_error' => true)
    noticed_error = segment.noticed_error

    assert noticed_error, 'Expected the segment to have a noticed error'
    assert_equal NRDeadEndJob::ERROR_MESSAGE, noticed_error.message
  end

  def test_captures_sidekiq_internal_errors
    exception = StandardError.new('bonk')
    noticed = []
    NewRelic::Agent.stub :notice_error, proc { |e| noticed.push(e) } do
      cli.handle_exception(exception)
    end

    assert_equal 1, noticed.size
    assert_equal exception, noticed.first
  end

  # Sidekiq::Job::Setter#perform_inline is expected to light up all registered
  # client and server middleware, and the lighting up of NR's server middleware
  # will produce a segment
  def test_works_with_perform_inline
    # Sidekiq version 6.4.2 ends up invoking String#constantize, which is only
    # delivered by ActiveSupport, which this test suite doesn't currently
    # include.
    skip 'This test requires Sidekiq v7+' unless NewRelic::Helper.version_satisfied?(Sidekiq::VERSION, '>=', '7.0.0')

    in_transaction do |txn|
      NRDeadEndJob.perform_inline
      segments = txn.segments.select { |s| s.name.eql?('Nested/OtherTransaction/SidekiqJob/NRDeadEndJob/perform') }

      assert_equal 1, segments.size, "Expected to find a single Sidekiq job segment, found #{segments.size}"
    end
  end

  def test_sidekiq_notice_only_once_default_is_false
    refute NewRelic::Agent.config[:sidekiq_notice_only_once], 'Expected default value for sidekiq_notice_only_once to be false'
  end
end
