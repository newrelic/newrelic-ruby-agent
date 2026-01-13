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
