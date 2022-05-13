# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../test_helper'

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
      NewRelic::Agent::Configuration::DEFAULTS[key_name][:external] || NewRelic::Agent::Configuration::DEFAULTS[key_name][:deprecated]
    end
    assert_empty @default_keys
  end

  def test_documented_all_named_instrumentation_files
    non_test_files.each do |file|
      next unless file.include?("new_relic/agent/instrumentation")

      lines_in(file).each_with_index do |line, index|
        dependency = line.match(NAMED_DEPENDENCY_PATTERN)
        if dependency
          name = dependency[1]
          disable_key = "disable_#{name}".to_sym
          instrumentation_key = "instrumentation.#{name}".to_sym

          has_disable_key = !!NewRelic::Agent::Configuration::DEFAULTS[disable_key]
          has_instrumentation_key = !!NewRelic::Agent::Configuration::DEFAULTS[instrumentation_key]

          assert has_instrumentation_key || has_disable_key,
            "#{file}:#{index + 1} - Document key `#{instrumentation_key}` found as name for instrumentation.\n"
        end
      end
    end
  end

  def non_test_files
    all_rb_files.reject { |filename| filename.include? 'test.rb' }
  end
end
