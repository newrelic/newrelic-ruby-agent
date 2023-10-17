# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'active_support'

class ActiveSupportLoggerTest < Minitest::Test
  include MultiverseHelpers
  setup_and_teardown_agent

  def setup
    NewRelic::Agent.manual_start
    @output = StringIO.new
    @logger = Logger.new(@output)
    @broadcasted_output = StringIO.new
    @broadcasted_logger = ActiveSupport::Logger.new(@broadcasted_output)
    @logger.extend(ActiveSupport::Logger.broadcast(@broadcasted_logger))

    @aggregator = NewRelic::Agent.agent.log_event_aggregator
    @aggregator.reset!
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  def test_broadcasted_logger_marked_skip_instrumenting
    assert @broadcasted_logger.instance_variable_get(:@skip_instrumenting), 'Broadcasted logger not set with @skip_instrumenting'
    assert_nil @logger.instance_variable_get(:@skip_instrumenting), 'Logger has @skip_instrumenting defined'
  end

  def test_logs_not_forwarded_by_broadcasted_logger
    message = 'Can you hear me, Major Tom?'

    @logger.add(Logger::DEBUG, message)

    assert_includes(@output.string, message)
    assert_includes(@broadcasted_output.string, message)

    # LogEventAggregator sees the log only once
    assert_equal 1, @aggregator.instance_variable_get(:@seen)
    assert_equal({'DEBUG' => 1}, @aggregator.instance_variable_get(:@seen_by_severity))
  end
end
