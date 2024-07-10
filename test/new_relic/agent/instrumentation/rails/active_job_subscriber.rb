# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../test_helper'
require 'new_relic/agent/instrumentation/active_job_subscriber'

module NewRelic::Agent::Instrumentation
  class DiscardMe < StandardError; end
  class RetryMe < StandardError; end
  class RetryStopped < StandardError; end

  class TestJob < ActiveJob::Base
    retry_on RetryMe
    retry_on RetryStopped, attempts: 1

    discard_on DiscardMe

    def perform(error = nil)
      # rails 6.0 job serialization breaks if you try to retry a job with a class as a param
      raise RetryMe if error == 'RetryMe'
      raise error if error

      rand(1138)
    end
  end

  class ActiveJobSubscriberTest < Minitest::Test
    NAME = 'perform.active_job'
    ID = 71741
    SUBSCRIBER = NewRelic::Agent::Instrumentation::ActiveJobSubscriber.new

    def setup
      # https://github.com/rails/rails/issues/37270
      (ActiveJob::Base.descendants << ActiveJob::Base).each(&:disable_test_adapter)
    end

    def test_segment_naming_with_unknown_method
      assert_equal 'Ruby/ActiveJob/default/Unknown',
        SUBSCRIBER.send(:metric_name, 'indecipherable', {job: TestJob.new})
    end

    # perform.active_job
    def test_perform_active_job
      job = TestJob.new
      in_transaction do |txn|
        job.perform_now
        validate_transaction(txn, 'perform')
      end
    end

    # enqueue_at.active_job
    def test_enqueue_at_active_job
      in_transaction do |txn|
        TestJob.set(wait_until: 7.hours.from_now).perform_later
        validate_transaction(txn, 'enqueue_at')
      end
    end

    # enqueue.active_job
    def test_enqueue_active_job
      in_transaction do |txn|
        TestJob.perform_later
        validate_transaction(txn, 'enqueue')
      end
    end

    # perform_start.active_job
    # enqueue_retry.active_job
    def test_perform_start_active_job_and_enqueue_retry_active_job
      in_transaction do |txn|
        # rails 6.0 job serialization breaks if you try to retry a job with a class as a param
        # this works fine if you aren't attempting to retry or you're using a later rails version
        job_arg = if Gem::Version.new(Rails::VERSION::STRING) < Gem::Version.new('6.1.0')
          'RetryMe'
        else
          RetryMe
        end
        TestJob.perform_now(job_arg)
        validate_transaction(txn, %w[enqueue_retry perform_start])
      end
    end

    # discard.active_job
    def test_discard_active_job
      in_transaction do |txn|
        TestJob.perform_now(DiscardMe)
        validate_transaction(txn, 'discard')
      end
    end

    def test_retry_stopped_active_job
      skip 'Notification requires Rails v6+' unless Gem::Version.new(Rails::VERSION::STRING) >= Gem::Version.new('6.0')

      in_transaction do |txn|
        assert_raises(RetryStopped) do
          TestJob.perform_now(RetryStopped)
        end
        validate_transaction(txn, 'retry_stopped')
      end
    end

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
