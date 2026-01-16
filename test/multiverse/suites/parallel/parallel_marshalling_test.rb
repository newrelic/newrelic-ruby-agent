# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require File.join(File.dirname(__FILE__), '..', '..', '..', 'new_relic', 'marshalling_test_cases')

if NewRelic::LanguageSupport.can_fork?

  class ParallelMarshallingTest < Minitest::Test
    include MultiverseHelpers
    include MarshallingTestCases

    setup_and_teardown_agent

    def setup
      super
      # Register SimpleCov at_exit once per process
      # Parallel's instrumentation registers its at_exit when worker is set up (before our block)
      # So we need to register ours BEFORE Parallel.map is called
      # LIFO: instrumentation's hook (last registered) runs first, SimpleCov (first registered) runs second
      if defined?(SimpleCov) && !@simplecov_at_exit_registered
        @simplecov_at_exit_registered = true
        at_exit do
          SimpleCov.result if SimpleCov.running
        end
      end
    end

    def around_each(&block)
      Parallel.map([1], in_processes: 1) do |item|
        yield
      end

      run_harvest
    end

    def test_sends_metrics_in_txn
      in_transaction do
        with_around_hook do
          NewRelic::Agent.record_metric('TXN_Boo', 42)
        end
        sleep 1
      end

      transmit_data

      results = $collector.calls_for('metric_data')

      assert results.any? { |r| r.metric_names.include?('TXN_Boo') },
        "Expected 'TXN_Boo' metric in one of #{results.size} metric_data calls"
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
