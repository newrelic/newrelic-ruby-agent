# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require File.join(File.dirname(__FILE__), '..', '..', '..', 'new_relic', 'marshalling_test_cases')

if NewRelic::LanguageSupport.can_fork?

  class ParallelMarshallingTest < Minitest::Test
    include MultiverseHelpers
    include MarshallingTestCases

    setup_and_teardown_agent

    def around_each(&block)
      Parallel.map([1], in_processes: 1) do |item|
        yield
      end

      run_harvest
    end

    # Override this test bc parallel works a little differently so we need to expect it differently
    def test_sends_metrics
      with_around_hook do
        NewRelic::Agent.record_metric('Boo', 42)
      end

      transmit_data

      results = $collector.calls_for('metric_data')
      assert results.any? { |r| r.metric_names.include?('Boo') },
        "Expected 'Boo' metric in one of #{results.size} metric_data calls"
    end
  end
end
