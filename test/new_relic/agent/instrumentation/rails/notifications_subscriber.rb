# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../test_helper'

module NewRelic
  module Agent
    module Instrumentation
      class NotificationsSubscriberTest < Minitest::Test
        DEFAULT_EVENT = 'any.event'

        def setup
          nr_freeze_process_time
          @subscriber = NotificationsSubscriber.new
          NewRelic::Agent.drop_buffered_data
          @id = fake_guid(32)
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_start_logs_notification_error
          logger = MiniTest::Mock.new

          NewRelic::Agent.stub :logger, logger do
            logger.expect :error, nil, [/Error during .* callback/]
            logger.expect :log_exception, nil, [:error, ArgumentError]

            in_transaction do |txn|
              @subscriber.stub :start_segment, -> { raise 'kaboom' } do
                @subscriber.start(DEFAULT_EVENT, @id, {})
              end

              assert_equal 1, txn.segments.size
            end
          end
          logger.verify
        end

        def test_finish_logs_notification_error
          logger = MiniTest::Mock.new

          NewRelic::Agent.stub :logger, logger do
            logger.expect :error, nil, [/Error during .* callback/]
            logger.expect :log_exception, nil, [:error, ArgumentError]

            in_transaction do |txn|
              @subscriber.stub :finish_segment, -> { raise 'kaboom' } do
                @subscriber.finish(DEFAULT_EVENT, @id, {})
              end

              assert_equal 1, txn.segments.size
            end
          end
          logger.verify
        end

        def test_segment_created_notsub
          NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)

          in_transaction do |txn|
            @subscriber.start(DEFAULT_EVENT, @id, {})

            @subscriber.finish(DEFAULT_EVENT, @id, {})
          end

          name = "Ruby/#{DEFAULT_EVENT}"
          spans = harvest_span_events!

          refute_empty(spans[1].select { |s| s[0]['name'] == name })
        end
      end
    end
  end
end
