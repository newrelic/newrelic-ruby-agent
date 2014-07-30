# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class OrphanedConfigTest < Minitest::Test
  include NewRelic::TestHelpers::FileSearching

  def setup
    @default_keys = ::NewRelic::Agent::Configuration::DEFAULTS.keys
  end

  def test_all_agent_config_keys_are_declared_in_default_source
    non_test_files = all_rb_files.reject { |filename| filename.include? 'test.rb' }

    non_test_files.each do |file|
      lines = File.read(file).split("\n")

      lines.each_with_index do |line, index|
        config_match = line.match(/Agent\.config\[:['"]?([a-z\._]+)['"]?\]/)
        next unless config_match

        config_keys = config_match.captures.map do |key|
          key.gsub("'", "").to_sym
        end

        config_keys.each do |key|
          msg = "#{file}:#{index} - Configuration key #{key} is not described in default_source.rb.\n"
          assert @default_keys.include?(key), msg
        end
      end
    end
  end

  AGENT_CONFIG_PATTERN      = /Agent\.config\[:['"]?([a-z\._]+)['"]?\s*\]/
  REGISTER_CALLBACK_PATTERN = /register_callback\(:['"]?([a-z\._]+)['"]?\)/
  NAMED_DEPENDENCY_PATTERN  = /^\s*named[ (]+\:?([a-z\._]+).*$/

  def test_all_default_source_config_keys_are_used_in_the_agent
    non_test_files = all_rb_files.reject { |filename| filename.include? 'test.rb' }

    non_test_files.each do |file|
      lines = File.read(file).split("\n")

      lines.each_with_index do |line, index|
        captures = []
        captures << line.scan(AGENT_CONFIG_PATTERN)
        captures << line.scan(REGISTER_CALLBACK_PATTERN)
        captures << line.scan(NAMED_DEPENDENCY_PATTERN).map(&method(:disable_name))

        next if captures.empty?

        captures.flatten.map do |key|
          @default_keys.delete key.gsub("'", "").to_sym
        end
      end
    end

    # Remove any config keys that are annotated with the 'dynamic_name' setting
    # This indicates that the names of these keys are constructed dynamically at
    # runtime, so we don't expect any explicit references to them in code.
    @default_keys.delete_if do |key_name|
      NewRelic::Agent::Configuration::DEFAULTS[key_name][:dynamic_name]
    end

    assert_empty @default_keys
  end

  def disable_name(names)
    names.map { |name| "disable_#{name}" }
  end
end
