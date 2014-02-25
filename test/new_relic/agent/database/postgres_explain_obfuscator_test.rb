# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
require 'new_relic/agent/database/postgres_explain_obfuscator'

module NewRelic::Agent::Database
  class PostgresExplainObfuscatorTest < Minitest::Test
    attr_reader :obfuscator

    def self.input_files
      fixture_dir = File.join(cross_agent_tests_dir, "postgres_explain_obfuscation")
      Dir["#{fixture_dir}/*.explain.txt"]
    end

    def self.name_for_input_file(input_file)
      File.basename(input_file, ".explain.txt")
    end

    input_files.each do |input_file|
      define_method("test_#{name_for_input_file(input_file)}_explain_plan_obfuscation") do
        explain             = File.read(input_file)
        expected_obfuscated = File.read(obfuscated_filename(input_file))
        actual_obfuscated   = PostgresExplainObfuscator.obfuscate(explain)
        assert_equal(expected_obfuscated, actual_obfuscated)
      end
    end

    def obfuscated_filename(query_file)
      query_file.gsub(".explain.", ".colon_obfuscated.")
    end
  end
end
