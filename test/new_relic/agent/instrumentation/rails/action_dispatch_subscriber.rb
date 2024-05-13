# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../test_helper'
require 'new_relic/agent/instrumentation/action_dispatch_subscriber'

module NewRelic::Agent::Instrumentation
  class TestMiddleware < ActionDispatch::MiddlewareStack::Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    end
  end

  class ActionDispatchSubscriberTest < Minitest::Test
    NAME = 'process_middleware.action_dispatch'
    ID = 1987 # 'Emperor of the Night'
    SUBSCRIBER = NewRelic::Agent::Instrumentation::ActionDispatchSubscriber.new

    def test_start
      in_transaction do |txn|
        time = Time.now.to_f
        SUBSCRIBER.start(NAME, ID, {middleware: TestMiddleware.name})
        segment = txn.segments.last

        assert_in_delta time, segment.start_time
        assert_equal "Ruby/ActionDispatch/#{TestMiddleware.name}/process_middleware", segment.name
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
      assert_equal "Ruby/ActionDispatch/#{TestMiddleware.name}/unknown",
        SUBSCRIBER.send(:metric_name, 'indecipherable', {middleware: TestMiddleware.name})
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

    # TODO: uncomment after the :disable_action_dispatch TODO comment in
    #       default_source.rb has been satisfied
    # def test_an_actual_middleware_call_based_event_processing
    #   with_config(disable_action_dispatch: false) do
    #     stack = ActionDispatch::MiddlewareStack.new
    #     stack.use TestMiddleware
    #     web_app = stack.build(proc { |env| [200, {}, []] })

    #     in_transaction do |txn|
    #       web_app.call({})
    #       segment = txn.segments.detect { |s| s.name.start_with?('Ruby/ActionDispatch') }

    #       assert segment
    #       assert_equal segment.name, "Ruby/ActionDispatch/#{TestMiddleware.name}/process_middleware"
    #     end
    #   end
    # end
  end
end
