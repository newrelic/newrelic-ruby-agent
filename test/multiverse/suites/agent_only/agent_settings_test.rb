# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class AgentSettingsTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent do |collector|
    collector.stub('connect', {'agent_run_id' => 42, 'apdex_t' => 2.0})
  end

  def test_sends_agent_settings_after_connect
    post = first_call_for('agent_settings')
    settings = post.body.first

    assert_equal '42', post.run_id
    assert_in_delta(2.0, settings['apdex_t'])
    refute settings.key?('license_key')
  end
end
