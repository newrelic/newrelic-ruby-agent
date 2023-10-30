# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'active_support'

class ActiveSupportBroadcastLoggerTest < Minitest::Test
  include MultiverseHelpers

  MESSAGE = 'Can you hear me, Major Tom?'

  def setup
    NewRelic::Agent.manual_start

    @output = StringIO.new
    @io_logger = Logger.new(@output)
    @output2 = StringIO.new
    @io_logger2 = Logger.new(@output2)
    @broadcast = ActiveSupport::BroadcastLogger.new(@io_logger, @io_logger2)
    @aggregator = NewRelic::Agent.agent.log_event_aggregator

    @aggregator.reset!
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  def test_broadcasted_logger_sends_one_log_event_per_add_call
    @broadcast.add(Logger::DEBUG, MESSAGE)

    assert_log_broadcasted_to_both_outputs
    assert_log_seen_once_by_new_relic('DEBUG')
  end

  def test_broadcasted_logger_sends_one_log_event_per_unknown_call
    @broadcast.unknown(MESSAGE)

    assert_log_broadcasted_to_both_outputs
    assert_log_seen_once_by_new_relic('ANY')
  end

  %w[debug info warn error fatal].each do |method|
    define_method("test_broadcasted_logger_sends_one_log_event_per_#{method}_call") do
      @broadcast.send(method.to_sym, MESSAGE)

      assert_log_broadcasted_to_both_outputs
      assert_log_seen_once_by_new_relic(method.upcase)
    end
  end

  private

  def assert_log_broadcasted_to_both_outputs
    assert_includes(@output.string, MESSAGE)
    assert_includes(@output2.string, MESSAGE)
  end

  def assert_log_seen_once_by_new_relic(severity)
    assert_equal(1, @aggregator.instance_variable_get(:@seen))
    assert_equal({severity => 1}, @aggregator.instance_variable_get(:@seen_by_severity))
  end
end
