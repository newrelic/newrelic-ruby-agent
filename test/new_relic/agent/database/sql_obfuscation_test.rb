# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))

module NewRelic::Agent::Database
  class SqlObfuscationTest < Minitest::Test
    attr_reader :obfuscator

    def self.input_files(subdir=nil)
      fixture_dir = File.join(cross_agent_tests_dir, "sql_obfuscation")
      fixture_dir = File.join(fixture_dir, subdir) if subdir
      Dir["#{fixture_dir}/*.sql"]
    end

    def self.adapter_from_input_file(input_file)
      case input_file
      when /\.postgres\.sql$/ then :postgresql
      when /\.mysql\.sql$/    then :mysql
      else nil
      end
    end

    def self.name_for_input_file(input_file)
      adapter = adapter_from_input_file(input_file)
      basename = File.basename(input_file)
      name = basename.gsub(/\.(postgres|mysql)?\.sql$/, '')
      name += "_#{adapter}" if adapter
      name
    end

    def obfuscated_filename(query_file)
      query_file.gsub(".sql", ".obfuscated")
    end

    def strip_comments(text)
      text.gsub(/^\s*#.*/, '').strip
    end

    def read_query(input_file)
      adapter = self.class.adapter_from_input_file(input_file)
      query = strip_comments(File.read(input_file))

      if adapter
        query = NewRelic::Agent::Database::Statement.new(query)
        query.adapter = adapter.to_sym
      end

      query
    end
    
    def self.create_regular_obfuscation_test(filename, type = "normal")
      name = name_for_input_file(filename)

      define_method("test_sql_obfuscation_#{type}_#{name}") do
        query               = read_query(filename)
        expected_obfuscated = File.read(obfuscated_filename(filename))
        actual_obfuscated   = NewRelic::Agent::Database.obfuscate_sql(query)
        assert_equal(expected_obfuscated, actual_obfuscated, "Failed to obfuscate #{type} query from #{filename}\nQuery: #{query}")
      end
    end

    # Normal queries
    input_files.each do |input_file|
      create_regular_obfuscation_test(input_file)
    end
    
    # Pathological queries
    input_files('pathological').each do |input_file|
      create_regular_obfuscation_test(input_file, "pathological")
    end

    # Malformed queries
    input_files('malformed').each do |input_file|
      name = name_for_input_file(input_file)

      define_method("test_sql_obfuscation_malformed_#{name}") do
        query = read_query(input_file)
        actual_obfuscated = NewRelic::Agent::Database.obfuscate_sql(query)
        assert_equal(NewRelic::Agent::Database::Obfuscator::FAILED_TO_OBFUSCATE_MESSAGE, actual_obfuscated, "Failed to obfuscate malformed query from #{input_file}\nQuery: #{query}")
      end
    end
  end
end
