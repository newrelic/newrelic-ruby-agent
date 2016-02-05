# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))

module NewRelic::Agent::Database
  class SqlObfuscationTest < Minitest::Test
    def self.create_input_statements(raw_query, dialects)
      dialects.map do |dialect|
        NewRelic::Agent::Database::Statement.new(raw_query, {:adapter => dialect})
      end
    end

    def build_failure_message(statement, acceptable_outputs, actual_output)
      msg = "Failed to obfuscate #{statement.adapter} query correctly.\n"
      msg << "Input:    #{statement.inspect}\n"
      if acceptable_outputs.size == 1
        msg << "Expected: #{acceptable_outputs.first}\n"
      else
        msg << "Acceptable outputs:\n"
        acceptable_outputs.each do |output|
          msg << "          #{output}\n"
        end
      end
      msg << "Actual:   #{actual_output}\n"
    end

    test_cases = load_cross_agent_test('sql_obfuscation/sql_obfuscation')
    test_cases.each do |test_case|
      name = test_case['name']
      query              = test_case['sql']
      acceptable_outputs = test_case['obfuscated']
      dialects           = test_case['dialects']

      # If the entire query is obfuscated because it's malformed, we use a
      # placeholder message instead of just '?', so add that to the acceptable
      # outputs.
      if test_case['malformed']
        acceptable_outputs << NewRelic::Agent::Database::Obfuscator::FAILED_TO_OBFUSCATE_MESSAGE
      end

      create_input_statements(query, dialects).each do |statement|
        define_method("test_sql_obfuscation_#{name}_#{statement.adapter}") do
          actual_obfuscated = NewRelic::Agent::Database.obfuscate_sql(statement)
          message = build_failure_message(statement, acceptable_outputs, actual_obfuscated)
          assert_includes(acceptable_outputs, actual_obfuscated, message)
        end
      end
    end
  end
end
