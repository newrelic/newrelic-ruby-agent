# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'fake_collector'

class LabelsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  EXPECTED     = [{'label_type' => 'Server', 'label_value' => 'East'}]
  YML_EXPECTED = [{'label_type' => 'Server', 'label_value' => 'Yaml'}]

  def test_yaml_makes_it_to_the_collector
    # Relies on the agent_only/config/newrelic.yml!
    trigger_agent_reconnect
    assert_connect_had_labels(YML_EXPECTED)
  end

  def test_labels_from_config_hash_make_it_to_the_collector
    with_config("labels" => { "Server" => "East" }) do
      trigger_agent_reconnect
      assert_connect_had_labels(EXPECTED)
    end
  end

  def test_labels_from_manual_start_hash_make_it_to_the_collector
    trigger_agent_reconnect(:labels => { "Server" => "East" })
    assert_connect_had_labels(EXPECTED)
  end

  def test_numeric_values_for_labels
    trigger_agent_reconnect(:labels => { "Server" => 42 })
    expected = [
      { 'label_type' => 'Server', 'label_value' => '42' }
    ]
    assert_connect_had_labels(expected)
  end

  def test_boolean_values_for_labels
    trigger_agent_reconnect(:labels => { "Server" => true })
    expected = [
      { 'label_type' => 'Server', 'label_value' => 'true' }
    ]
    assert_connect_had_labels(expected)
  end

  # All testing of string parsed label pairs should go through the cross agent
  # test file for labels. Our dictionary passing is custom to Ruby, though.
  load_cross_agent_test("labels").each do |testcase|
    define_method("test_#{testcase['name']}_from_config_string") do
      with_config("labels" => testcase["labelString"]) do
        trigger_agent_reconnect
        assert_connect_had_labels(testcase["expected"])
      end
    end

    define_method("test_#{testcase['name']}_from_manual_start") do
      trigger_agent_reconnect(:labels => testcase["labelString"])
      assert_connect_had_labels(testcase["expected"])
    end

    define_method("test_#{testcase['name']}_from_env") do
      begin
        # Value must be here before reset for EnvironmentSource to see it
        ENV['NEW_RELIC_LABELS'] = testcase["labelString"]
        NewRelic::Agent.config.reset_to_defaults

        trigger_agent_reconnect
        assert_connect_had_labels(testcase["expected"])
      ensure
        ENV['NEW_RELIC_LABELS'] = nil
      end
    end
  end

  def assert_connect_had_labels(expected)
    result = $collector.calls_for('connect').last['labels']
    assert_equal expected.sort_by { |h| h['label_type']},
                 result.sort_by { |h| h['label_type']}
  end
end
