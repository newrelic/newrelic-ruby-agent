# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class AgentSettingsTest < Minitest::Test
  include MultiverseHelpers

  def teardown
    teardown_agent
  end

  def test_sends_agent_settings_after_connect
    setup_agent do |collector|
      collector.stub('connect', {'agent_run_id' => 42, 'apdex_t' => 2.0})
    end

    post = first_call_for('agent_settings')
    settings = post.body.first

    assert_equal '42', post.run_id
    assert_in_delta(2.0, settings['apdex_t'])
    refute settings.key?('license_key')
  end

  def test_sends_agent_settings_again_on_reconnect
    setup_agent do |collector|
      collector.stub('connect', {'agent_run_id' => 1, 'apdex_t' => 2.0})
    end

    $collector.stub('connect', {'agent_run_id' => 2, 'apdex_t' => 3.0})
    trigger_agent_reconnect
    posts = $collector.calls_for('agent_settings')

    assert_equal %w[1 2], posts.map(&:run_id)
    assert_in_delta(3.0, posts.last.body.first['apdex_t'])
  end

  def test_does_not_send_agent_settings_when_disabled
    setup_agent(:enable_agent_settings => false)

    assert_empty $collector.calls_for('agent_settings')
  end
end
