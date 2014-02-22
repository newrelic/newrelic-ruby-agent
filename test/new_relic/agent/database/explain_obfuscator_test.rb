# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
require 'new_relic/agent/database/explain_obfuscator'

module NewRelic::Agent::Database
  class ExplainObfuscatorTest < Minitest::Test
    attr_reader :obfuscator

    def self.query_files
      fixture_dir = File.join(cross_agent_tests_dir, "postgres_explain_obfuscation")
      Dir["#{fixture_dir}/*.query.txt"]
    end

    def self.query_files_with_escapes
      fixture_dir = File.join(cross_agent_tests_dir, "postgres_explain_obfuscation", "with_escape_sequences")
      Dir["#{fixture_dir}/*.query.txt"]
    end

    def self.name_for_query_file(query_file)
      File.basename(query_file, ".query.txt")
    end

    query_files.each do |query_file|
      define_method("test_#{name_for_query_file(query_file)}_explain_plan_obfuscation") do
        query   = File.read(query_file)
        explain = File.read(explain_filename(query_file))
        obfuscated = File.read(obfuscated_filename(query_file))

        result = ExplainObfuscator.obfuscate(query, explain)
        assert_equal(obfuscated, result)
      end
    end

    query_files_with_escapes.each do |query_file|
      # For tests in this category, we just punt on obfuscation and drop the
      # whole thing.
      define_method("test_#{name_for_query_file(query_file)}_escaped_explain_plan_obfuscation") do
        query   = File.read(query_file)
        explain = File.read(explain_filename(query_file))

        result = ExplainObfuscator.obfuscate(query, explain)
        assert_equal('', result, build_message(query, explain))
      end
    end

    def build_message(query, explain, obfuscated=nil)
      "Failed to correctly obfuscate explain for query:\n#{query}"
    end

    def explain_filename(query_file)
      query_file.gsub(".query.", ".explain.")
    end

    def obfuscated_filename(query_file)
      query_file.gsub(".query.", ".obfuscated.")
    end
  end
end
