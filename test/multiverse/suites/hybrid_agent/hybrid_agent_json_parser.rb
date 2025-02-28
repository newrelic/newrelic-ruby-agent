# # This file is distributed under New Relic's license terms.
# # See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# # frozen_string_literal: true

# module HybridAgentJsonParser
#   # TODO: define all commands in a module and include that module
#   # TODO: define all assertion -> rule -> parameters as methods
#   # TODO: consider defining a JSON parser that would take the entire
#   # hybrid_agent.json file and turn the camel casing into snake
#   test_cases = load_cross_agent_test('hybrid_agent')
#   test_cases.each do |test_case|
#     name = test_case["testDescription"].downcase.gsub(' ', '_')

#     define_method("test_hybrid_agent_#{name}") do
#       operations = test_case["operations"]
#       operations.map do |o|
#         parse_operation(o)
#       end

#       txns = harvest_transaction_events![1]
#       spans = harvest_span_events![1]

#       verify_agent_output(txns, test_case["agentOutput"]["transactions"])
#       verify_agent_output(spans, test_case["agentOutput"]["spans"])
#     end
#   end

#   def parse_operation(operation)
#     command = operation["command"].gsub!(/(.)([A-Z])/,'\1_\2').downcase.to_sym
#     parameters = operation[0]['parameters'].transform_keys {|k| k.gsub(/(.)([A-Z])/,'\1_\2').downcase.to_sym }

#     if operation["childOperation"]
#       send(command, parameters) do
#         binding.irb
#         parse_operation

#         parse_assertions if operation["assertions"]
#       end
#     else
#       binding.irb
#       send(command, parameters)
#       parse_assertions if operation["assertions"]
#     end
#   end

#   def parse_assertions(assertions)
#     # we would either need to change the names to the right case
#     # or define methods with casing matching the JSON file
#     # for all the objects under test

#     # for this one, the parameters are what would need to get
#     # translated, since we're explicitly using cases for the
#     # various operators
#     assertions.each do |assertion|
#       rule = assertion["rule"]
#       case rule["operator"]
#       when "Equals"
#         assert_equal eval(rule["parameters"]["left"]), eval(rule["parameters"]["right"])
#       when "NotValid"
#         assert_nil eval(rule["parameters"]["object"])
#       else
#         raise 'missing rule case for assertions!'
#       end
#     end
#   end

#   def verify_agent_output(harvest, output)
#     # some of the keys for spans are different than the test
#     # ex. entryPoint is nr.entryPoint
#     # other keys will need to be translated from camel to snake case
#     # ex. parentName
#     output = snakeify(output)

#     harvest.each do |h|
#       break if h.empty?
#       if output
#         output.each do |o|
#           if o && h
#             assert h >= o
#           end
#         end
#       end
#     end
#   end

#   def snakify(output)
#     output.map do |o|
#       o.transform_keys do |k|
#         if k == 'entryPoint'
#           k = 'nr.entryPoint'
#         else
#           k.gsub(/(.)([A-Z])/,'\1_\2').downcase
#         end
#       end
#     end
#   end
# end
