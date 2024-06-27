# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class LogStasherInstrumentationTest < Minitest::Test
  include MultiverseHelpers

  def json_user_set_log_hash
    {
      'level' => :warn,
      'message' => 'A trex is near',
      'source' => '127.0.0.1',
      'tags' => ['log'],
      '@timestamp' => '2024-06-24T23:53:54.626Z'
    }
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

  def setup
    @written = StringIO.new

    # 
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

  def test_level_is_recorded
    in_transaction do
      LogStasher.build_logstash_event({"level"=>:info, "message"=>"hi there"}, ['log'])
    end
    _, events = @aggregator.harvest!

    assert_equal :info, events[0][1]['level']
    assert_metrics_recorded(%w[Logging/lines/info])
  end

  def test_logs_without_levels_are_unknown
    in_transaction do
      LogStasher.build_logstash_event(json_log_hash, ['log'])
    end
    _, events = @aggregator.harvest!

    assert_equal 'UNKNOWN', events[0][1]['level']
    assert_metrics_recorded(%w[Logging/lines/UNKNOWN])
  end

  def test_logs_without_messages_are_empty_strings
    in_transaction do
      LogStasher.build_logstash_event(json_log_hash, ['log'])
    end
    _, events = @aggregator.harvest!

    assert_equal '', events[0][1]['message']
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

  def test_log_decorating_enabled_records_new_relic_metrics
    with_config(:'application_logging.local_decorating.enabled' => true) do
      LogStasher.warn('yikes')
    end
    logfile = JSON.parse(@written.string)

    assert logfile.key?('entity.name')
    assert logfile.key?('entity.type')
    assert logfile.key?('hostname')
  end

  def test_log_decorating_enabled_records_new_relic_metrics
    with_config(:'application_logging.local_decorating.enabled' => false) do
      LogStasher.warn('yikes')
    end
    logfile = JSON.parse(@written.string)

    refute logfile.key?('entity.name')
    refute logfile.key?('entity.type')
    refute logfile.key?('hostname')
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
