# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))

module NewRelic::Agent::Database
  class SqlObfuscationTest < Minitest::Test
    attr_reader :obfuscator

    def self.input_files
      fixture_dir = File.join(cross_agent_tests_dir, "sql_obfuscation")
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

    input_files.each do |input_file|
      name = name_for_input_file(input_file)
      adapter = adapter_from_input_file(input_file)

      define_method("test_sql_obfuscation_#{name}") do
        query               = File.read(input_file)
        expected_obfuscated = File.read(obfuscated_filename(input_file))

        query = strip_comments(query)

        if adapter
          query = NewRelic::Agent::Database::Statement.new(query)
          query.adapter = adapter.to_sym
        end

        actual_obfuscated = NewRelic::Agent::Database.obfuscate_sql(query)
        assert_equal(expected_obfuscated, actual_obfuscated)
      end
    end
  end
end
