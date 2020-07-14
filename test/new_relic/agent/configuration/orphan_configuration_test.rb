# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class OrphanedConfigTest < Minitest::Test
  include NewRelic::TestHelpers::FileSearching
  include NewRelic::TestHelpers::ConfigScanning

  def setup
    @default_keys = ::NewRelic::Agent::Configuration::DEFAULTS.keys
  end

  def test_all_agent_config_keys_are_declared_in_default_source
    non_test_files.each do |file|
      lines_in(file).each_with_index do |line, index|
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

  def test_all_default_source_config_keys_are_used_in_the_agent
    scan_and_remove_used_entries @default_keys, non_test_files

    # Remove any config keys that are annotated with the 'external' setting
    # This indicates that these keys are referenced and implemented in
    # an external gem, so we don't expect any explicit references to them
    # in the core gem's code.
    @default_keys.delete_if do |key_name|
      NewRelic::Agent::Configuration::DEFAULTS[key_name][:external]
    end
    assert_empty @default_keys
  end

  def test_documented_all_named_instrumentation_files
    non_test_files.each do |file|
      next unless file.include?("new_relic/agent/instrumentation")

      lines_in(file).each_with_index do |line, index|
        captures = line.scan(NAMED_DEPENDENCY_PATTERN).map(&method(:disable_name))

        captures.flatten.map do |key|
          refute NewRelic::Agent::Configuration::DEFAULTS[key.to_sym].nil?, "#{file}:#{index+1} - Document key `#{key}` found as name for instrumentation.\n"
        end
      end
    end
  end

  def non_test_files
    all_rb_files.reject { |filename| filename.include? 'test.rb' }
  end
end
