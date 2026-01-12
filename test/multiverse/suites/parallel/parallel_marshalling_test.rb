# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require File.join(File.dirname(__FILE__), '..', '..', '..', 'new_relic', 'marshalling_test_cases')

if NewRelic::LanguageSupport.can_fork?

  class ParallelMarshallingTest < Minitest::Test
    include MultiverseHelpers
    include MarshallingTestCases

    setup_and_teardown_agent do
      # Start the pipe channel listener like the Parallel instrumentation does
      NewRelic::Agent.manual_start(
        :start_channel_listener => true,
        :sync_startup => false
      ) unless NewRelic::Agent.agent&.started?
    end

    def around_each(&block)
      # Use Parallel.map to verify our instrumentation correctly sets up pipe communication
      # This ensures the instrumentation hooks into Parallel and invokes register_report_channel,
      # after_fork, and flush_pipe_data automatically when Parallel is actually used
      Parallel.map([1], in_processes: 1) do |item|
        # Execute the test in the child process
        block.call
      end

      # Give the pipe listener time to receive and process the data
      sleep 1.0
      # Force harvest to pick up any pending pipe data
      run_harvest
    end

    def after_each
      NewRelic::Agent::PipeChannelManager.listener.stop
    end

    # Override first_call_for to handle the fact that Parallel.map may generate
    # additional calls beyond what the test expects. We just return the first call
    # that has data, which is what the tests care about.
    def first_call_for(subject)
      items = $collector.calls_for(subject)
      refute_predicate items.size, :zero?, "Expected at least one call for '#{subject}'"
      items.first
    end
  end

end
