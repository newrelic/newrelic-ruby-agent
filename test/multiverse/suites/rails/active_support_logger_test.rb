# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require './app'

if defined?(ActiveSupport::Logger)
  class ActiveSupportLoggerTest < Minitest::Test
    include MultiverseHelpers
    setup_and_teardown_agent

    def rails_7_1?
      Gem::Version.new(::Rails::VERSION::STRING) >= Gem::Version.new('7.1.0')
    end

    def setup
      @output = StringIO.new
      @logger = Logger.new(@output)
      @broadcasted_output = StringIO.new
      @broadcasted_logger = ActiveSupport::Logger.new(@broadcasted_output)
      @logger.extend(ActiveSupport::Logger.broadcast(@broadcasted_logger)) unless rails_7_1?

      @aggregator = NewRelic::Agent.agent.log_event_aggregator
      @aggregator.reset!
    end

    def test_broadcasted_logger_marked_skip_instrumenting
      skip 'Rails 7.1. Active Support Logger instrumentation broken, see #2245' if rails_7_1?

      assert @broadcasted_logger.instance_variable_get(:@skip_instrumenting), 'Broadcasted logger not set with @skip_instrumenting'
      assert_nil @logger.instance_variable_get(:@skip_instrumenting), 'Logger has @skip_instrumenting defined'
    end

    def test_logs_not_forwarded_by_broadcasted_logger
      skip 'Rails 7.1. Active Support Logger instrumentation broken, see #2245' if rails_7_1?

      message = 'Can you hear me, Major Tom?'

      @logger.add(Logger::DEBUG, message)

      assert_includes(@output.string, message)
      assert_includes(@broadcasted_output.string, message)

      # LogEventAggregator sees the log only once
      assert_equal 1, @aggregator.instance_variable_get(:@seen)
      assert_equal({'DEBUG' => 1}, @aggregator.instance_variable_get(:@seen_by_severity))
    end
  end
end
