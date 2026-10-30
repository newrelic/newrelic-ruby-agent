# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ForkBufferedDataTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_forked_child_does_not_resend_parents_log_events
    skip 'requires Process._fork (Ruby 3.1+)' unless NewRelic::LanguageSupport.can_fork? && Process.respond_to?(:_fork)

    NewRelic::Agent.agent.log_event_aggregator.record('parent line', 'INFO')

    pid = Process.fork do
      NewRelic::Agent.agent.shutdown
      exit!(0)
    end
    Process.wait(pid)

    NewRelic::Agent.agent.send(:harvest_and_send_log_event_data)

    messages = $collector.calls_for(:log_event_data).flat_map { |post| post.logs.map { |log| log['message'] } }

    assert_equal ['parent line'], messages
  end
end
