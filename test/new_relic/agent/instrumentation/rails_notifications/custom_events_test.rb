# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../test_helper'

module NewRelic::Agent::Instrumentation
  class CustomEventsTest < Minitest::Test
    # def teardown
    #   Object.remove_const(::Rails::VERSION::MAJOR)
    #   Object.remove_const(::Rails::VERSION)
    #   Object.remove_const(::Rails)
    #   Object.remove_const(::ActiveSupport::Notifications)
    #   Object.remove_const(::ActiveSupport::IsolatedExecutionState)
    #   Object.remove_const(::ActiveSupport)
    # end

    # def test_it
    #    Object.const_set(::Rails, 0)

    #   # NewRelic::Agent.stub :config, -> { raise 'kaboom' } do
    #   #   DependencyDetection.detect!
    #   # end
    # end

    def logger_not_expecting_instrumentation
      @logger_not_expecting_instrumentation ||= begin
        logger = MiniTest::Mock.new
        def logger.debug(msg = nil); end
        def logger.info(msg = '')
          raise 'Custom events instrumentation was not expected!' if msg.include?('ActiveSupport custom events')
        end
        logger
      end
    end

    def test_rails_version_is_not_set
      NewRelic::Agent.stub :logger, logger_not_expecting_instrumentation do
        DependencyDetection.detect!
      end
    end

    def test_rails_version_is_too_low
      # Object.const_set(:R)
      NewRelic::Agent.stub :logger, logger_not_expecting_instrumentation do
        DependencyDetection.detect!
      end
    end

    def test_active_support_notifications_is_not_set

    end

    def test_active_support_isolated_execution_state_is_not_set

    end

    def test_instrumentation_is_disabled

    end

    def test_topics_list_is_empty
    end

    def test_topics_have_already_been_subscribed_to
    end
  end
end
