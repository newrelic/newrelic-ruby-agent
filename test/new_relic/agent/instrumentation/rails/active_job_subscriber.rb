# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../test_helper'
require 'new_relic/agent/instrumentation/active_job_subscriber'

module NewRelic::Agent::Instrumentation
  class RetryMe < StandardError; end
  class DiscardMe < StandardError; end

  class TestJob < ActiveJob::Base
    retry_on RetryMe

    discard_on DiscardMe

    def perform(error = nil)
      raise error if error

      rand(1138)
    end
  end

  class ActiveJobSubscriberTest < Minitest::Test
    NAME = 'perform.active_job'
    ID = 71741
    SUBSCRIBER = NewRelic::Agent::Instrumentation::ActiveJobSubscriber.new

    def test_start
      in_transaction do |txn|
        time = Time.now.to_f
        SUBSCRIBER.start(NAME, ID, {job: TestJob.new})
        segment = txn.segments.last

        assert_in_delta time, segment.start_time
        assert_equal 'Ruby/ActiveJob/default/perform', segment.name
      end
    end

    def test_start_when_not_traced
      SUBSCRIBER.state.stub :is_execution_traced?, false do
        in_transaction do |txn|
          SUBSCRIBER.start(NAME, ID, {})

          assert_empty txn.segments
        end
      end
    end

    def test_start_with_exception_raised
      logger = MiniTest::Mock.new

      NewRelic::Agent.stub :logger, logger do
        logger.expect :error, nil, [/Error during .* callback/]
        logger.expect :log_exception, nil, [:error, ArgumentError]

        in_transaction do |txn|
          SUBSCRIBER.stub :start_segment, -> { raise 'kaboom' } do
            SUBSCRIBER.start(NAME, ID, {})
          end

          assert_equal 1, txn.segments.size
        end
      end
      logger.verify
    end

    def test_segment_naming_with_unknown_method
      assert_equal 'Ruby/ActiveJob/default/unknown',
        SUBSCRIBER.send(:metric_name, 'indecipherable', {job: TestJob.new})
    end

    def test_finish
      in_transaction do |txn|
        started_segment = NewRelic::Agent::Tracer.start_transaction_or_segment(name: NAME, category: :testing)
        SUBSCRIBER.push_segment(ID, started_segment)

        time = Time.now.to_f
        SUBSCRIBER.finish(NAME, ID, {})
        segment = txn.segments.last

        assert_in_delta time, segment.end_time
        assert_predicate(segment, :finished?)
      end
    end

    def test_finish_with_exception_payload
      skip_unless_minitest5_or_above

      exception_object = StandardError.new
      noticed = false
      segment = MiniTest::Mock.new
      segment.expect :notice_error, nil, [exception_object]
      SUBSCRIBER.stub(:pop_segment, segment, [ID]) do
        SUBSCRIBER.finish(NAME, ID, {exception_object: exception_object})
      end

      segment.verify
    end

    def test_finish_with_exception_raised
      logger = MiniTest::Mock.new

      NewRelic::Agent.stub :logger, logger do
        logger.expect :error, nil, [/Error during .* callback/]
        logger.expect :log_exception, nil, [:error, RuntimeError]

        in_transaction do |txn|
          SUBSCRIBER.state.stub :is_execution_traced?, -> { raise 'kaboom' } do
            SUBSCRIBER.finish(NAME, ID, {})
          end

          assert_equal 1, txn.segments.size
        end
      end
      logger.verify
    end

    def test_finish_when_not_tracing
      state = MiniTest::Mock.new
      state.expect :is_execution_traced?, false

      SUBSCRIBER.stub :state, state do
        assert_nil SUBSCRIBER.finish(NAME, ID, {})
      end
    end

    def test_finish_segment_when_a_segment_does_not_exist
      SUBSCRIBER.stub :pop_segment, nil, [ID] do
        assert_nil SUBSCRIBER.send(:finish_segment, ID, {})
      end
    end

    # perform.active_job
    def test_an_actual_job_event_perform
      job = TestJob.new
      in_transaction do |txn|
        job.perform_now
        validate_transaction(txn, 'perform')
      end
    end

    # enqueue_at.active_job
    def test_an_actual_job_event_enqueue_at
      in_transaction do |txn|
        TestJob.set(wait_until: 7.hours.from_now).perform_later
        validate_transaction(txn, 'enqueue_at')
      end
    end

    # enqueue.active_job
    def test_an_actual_job_event_enqueue
      in_transaction do |txn|
        TestJob.perform_later
        validate_transaction(txn, 'enqueue')
      end
    end

    # perform_start.active_job
    # enqueue_retry.active_job
    def test_an_actual_job_event_retry
      in_transaction do |txn|
        TestJob.perform_now(RetryMe)
        validate_transaction(txn, %w[enqueue_retry perform_start])
      end
    end

    # discard.active_job
    def test_an_actual_job_event_retry
      in_transaction do |txn|
        TestJob.perform_now(DiscardMe)
        validate_transaction(txn, 'discard')
      end
    end

    # TODO: test for retry_stopped
    # retry_stopped.active_job
    # def test_an_actual_job_event_retry
    #   in_transaction do |txn|
    #     # ???
    #     validate_transaction(txn, 'retry_stopped')
    #   end
    # end

    private

    def validate_transaction(txn, methods = [])
      methods = Array(methods)
      segments = txn.segments.select { |s| s.name.start_with?('Ruby/ActiveJob') }

      refute_empty segments

      methods.each do |method|
        segment = segments.detect { |s| s.name == "Ruby/ActiveJob/default/#{method}" }

        assert segment
        assert_equal 'ActiveJob::QueueAdapters::AsyncAdapter', segment.params[:adapter].class.name
      end
    end
  end
end
