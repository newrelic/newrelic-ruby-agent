# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')
require 'fake_collector'
require 'multiverse_helpers'

class LabelsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  EXPECTED     = [{'label_type' => 'Server', 'label_value' => 'East'}]
  YML_EXPECTED = [{'label_type' => 'Server', 'label_value' => 'Yaml'}]

  def after_setup
    $collector.reset
    make_sure_agent_reconnects({})
  end

  def test_yaml_makes_it_to_the_collector
    # Relies on the agent_only/config/newrelic.yml!
    NewRelic::Agent.manual_start
    assert_connect_had_labels(YML_EXPECTED)
  end

  def test_labels_from_config_hash_make_it_to_the_collector
    with_config("labels" => { "Server" => "East" }) do
      NewRelic::Agent.manual_start
      assert_connect_had_labels(EXPECTED)
    end
  end

  def test_labels_from_config_string_make_it_to_the_collector
    with_config(:labels => "Server:East;") do
      NewRelic::Agent.manual_start
      assert_connect_had_labels(EXPECTED)
    end
  end

  def test_labels_from_manual_start_string_make_it_to_the_collector
    NewRelic::Agent.manual_start(:labels => "Server:East;")
    assert_connect_had_labels(EXPECTED)
  end

  def test_labels_from_manual_start_hash_make_it_to_the_collector
    NewRelic::Agent.manual_start(:labels => { "Server" => "East" })
    assert_connect_had_labels(EXPECTED)
  end

  def test_labels_from_env_string_make_it_to_the_collector
    # Value must be here before reset for EnvironmentSource to see it
    ENV['NEW_RELIC_LABELS'] = "Server:East;"
    NewRelic::Agent.config.reset_to_defaults

    NewRelic::Agent.manual_start
    assert_connect_had_labels(EXPECTED)
  ensure
    ENV['NEW_RELIC_LABELS'] = nil
  end

  def assert_connect_had_labels(expected)
    result = $collector.calls_for('connect').first['labels']
    assert_equal expected, result
  end
end
