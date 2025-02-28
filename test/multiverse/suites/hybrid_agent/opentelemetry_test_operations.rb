# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true
require 'opentelemetry'
require 'newrelic_rpm'

module OpenTelemetryTestOperations
  # def do_work_in_span(span_kind:, span_name:)
  #   # create an OpenTelemetry Span
  # end
end

  # test_cases = load_cross_agent_test('hybrid_agent')
  # test_cases.each do |test_case|
  #   binding.irb
  #   name = test_case["testDescription"].downcase.gsub(' ', '_')
  #   operations = test_case["operations"]
  #   operations.each do |o|
  #     # transfer all the camel case to snake case
  #     o["command"].gsub!(/(.)([A-Z])/,'\1_\2').downcase.to_sym # creates the matching method name
  #     o["parameters"]
  #     # eventually do
  #     # send(command, parameters)
  #     # with parameters as {param1: 'val', param2: 'val'}
  #     # check for child params
  #     # jump into the assertion
  #   end

  #   define_method("test_hybrid_agent_#{name}") do
  #   end
  # end
