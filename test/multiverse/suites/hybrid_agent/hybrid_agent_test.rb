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
  end

  # This method, when returning a non-empty array, will cause the tests defined in the
  # JSON file to be skipped if they're not listed here. Useful for focusing on specific
  # failing tests.
  # It looks for the snake cased version of the testDescription field in the JSON
  # Ex: %w[does_not_create_segment_without_a_transaction] would only run
  # `"testDescription": "Does not create segment without a transaction"`
  def focus_tests
    %w[]
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

        harvest_and_verify_agent_output(test_case['agentOutput'])
      else
        skip('marked pending by exclusion from #focus_tests')
      end
    end
  end
end
