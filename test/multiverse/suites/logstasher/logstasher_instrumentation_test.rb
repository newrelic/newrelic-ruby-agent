# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'ostruct'

class LogStasherInstrumentationTest < Minitest::Test
  include MultiverseHelpers

  def setup
    @written = StringIO.new

    # Give LogStasher's setup method a new place to write logs to, as well as
    # skip a config check, controller_monkey_patch, that otherwise causes an error
    LogStasher.setup(OpenStruct.new(logger_path: @written, controller_monkey_patch: false))

    # required for build_logstasher_event method
    LogStasher.field_renaming = {}
    @aggregator = NewRelic::Agent.agent.log_event_aggregator

    NewRelic::Agent.instance.stats_engine.reset!
    NewRelic::Agent.instance.log_event_aggregator.reset!
  end

  def teardown
    NewRelic::Agent.instance.stats_engine.reset!
    NewRelic::Agent.instance.log_event_aggregator.reset!
  end

  def json_log_hash
    {
      :identifier => 'dinosaurs/_dinosaur.html.erb',
      :name => 'render_partial.action_view',
      :request_id => '01234-abcde-56789-fghij',
      'source' => '127.0.0.1',
      'tags' => [],
      '@timestamp' => '2024-06-24T23:55:59.497Z'
    }
  end

  def test_level_is_recorded
    in_transaction do
      LogStasher.build_logstash_event({'level' => :info, 'message' => 'hi there'}, ['log'])
    end
    _, events = @aggregator.harvest!

    assert_equal 'INFO', events[0][1]['level']
    assert_metrics_recorded(%w[Logging/lines/INFO])
  end

  def test_logs_without_levels_are_unknown
    in_transaction do
      LogStasher.build_logstash_event(json_log_hash, ['log'])
    end
    _, events = @aggregator.harvest!

    assert_equal 'UNKNOWN', events[0][1]['level']
    assert_metrics_recorded(%w[Logging/lines/UNKNOWN])
  end

  def test_logs_without_messages_are_not_added
    in_transaction do
      LogStasher.build_logstash_event(json_log_hash, ['log'])
    end
    _, events = @aggregator.harvest!

    refute events[0][1]['message']
  end

  def test_attributes_added_to_payload
    in_transaction do
      LogStasher.build_logstash_event(json_log_hash, ['log'])
    end
    _, events = @aggregator.harvest!

    assert events[0][1]['attributes'].key?(:identifier)
    assert events[0][1]['attributes'].key?(:name)
    assert events[0][1]['attributes'].key?('source')
  end

  def test_records_trace_linking_metadata
    in_transaction do
      LogStasher.warn('yikes')
    end

    _, events = @aggregator.harvest!
    assert events[0][1]['trace.id']
    assert events[0][1]['span.id']
  end

  def test_log_decorating_records_linking_metadata_when_enabled
    with_config(:'application_logging.local_decorating.enabled' => true) do
      in_transaction do
        LogStasher.warn('yikes')
      end
    end
    log_output = @written.string

    assert_match(/yikes/, log_output)
    assert_match(/entity\.name|trace\.id|span\.id|NR-LINKING/, log_output)
  end

  def test_log_decorating_does_not_record_linking_metadata_when_disabled
    with_config(:'application_logging.local_decorating.enabled' => false) do
      in_transaction do
        LogStasher.warn('yikes')
      end
    end
    log_output = @written.string

    assert_match(/yikes/, log_output)
    refute_match(/entity\.name|trace\.id|span\.id|NR-LINKING/, log_output)
  end

  def test_no_instrumentation_when_disabled
    with_config(:'instrumentation.logstasher' => 'disabled') do
      LogStasher.warn('yikes')
    end
    _, events = @aggregator.harvest!

    assert_empty(events)
  end

  def test_enabled_returns_false_when_disabled
    with_config(:'instrumentation.logstasher' => 'disabled') do
      refute_predicate NewRelic::Agent::Instrumentation::LogStasher, :enabled?
    end
  end

  def test_enabled_returns_true_when_enabled
    with_config(:'instrumentation.logstasher' => 'auto') do
      assert_predicate NewRelic::Agent::Instrumentation::LogStasher, :enabled?
    end
  end
end
