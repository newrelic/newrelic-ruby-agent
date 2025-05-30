# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'opentelemetry'
require_relative 'commands'
require_relative 'assertion_parameters'
require_relative 'parsing_helpers'

class HybridAgentTest < Minitest::Test
  include Commands
  include AssertionParameters
  include ParsingHelpers

  def setup
    @tracer = OpenTelemetry.tracer_provider.tracer

    # in order to inject headers, there must be a parent account ID and a
    # parent application ID
    @config = {
      :account_id => '190',
      :primary_application_id => '46954'
    }
    NewRelic::Agent.config.add_config_for_testing(@config)
  end

  def teardown
    NewRelic::Agent.instance.transaction_event_aggregator.reset!
    NewRelic::Agent.instance.span_event_aggregator.reset!
  end

  # This method, when returning a non-empty array, will cause the tests defined in the
  # JSON file to be skipped if they're not listed here. Useful for focusing on specific
  # failing tests.
  # It looks for the snake cased version of the testDescription field in the JSON
  # Ex: %w[does_not_create_segment_without_a_transaction] would only run
  # `"testDescription": "Does not create segment without a transaction"`
  #
  # Now that we're starting to implement, use this to add tests individually
  # until the full suite can be run on the CI
  def focus_tests
    %w[
      creates_opentelemetry_segment_in_a_transaction
      creates_new_relic_span_as_child_of_opentelemetry_span
      does_not_create_segment_without_a_transaction
      starting_transaction_tests
      opentelemetry_api_and_new_relic_api_can_inject_outbound_trace_context
      inbound_distributed_tracing_tests
    ]
  end

  test_cases = load_cross_agent_test('hybrid_agent')
  test_cases.each do |test_case|
    name = test_case['testDescription'].downcase.tr(' ', '_')

    define_method("test_hybrid_agent_#{name}") do
      if focus_tests.empty? || focus_tests.include?(name)
        puts "TEST: #{name}" if ENV['ENABLE_OUTPUT']

        operations = test_case['operations']
        operations.map do |o|
          parse_operation(o)
        end

        verify_agent_output(test_case['agentOutput'])
      else
        skip('marked pending by exclusion from #focus_tests')
      end
    end
  end
end
