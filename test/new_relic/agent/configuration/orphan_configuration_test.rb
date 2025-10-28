# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

class OrphanedConfigTest < Minitest::Test
  include NewRelic::TestHelpers::FileSearching
  include NewRelic::TestHelpers::ConfigScanning

  # :automatic_custom_instrumentation_method_list - the tranform proc handles all processing, no other reference exists
  # :'agent_control.enabled' - the config is set by environment variable in agent control, the symbol config is not used
  # :'agent_control.health.delivery_location - the config is set by environment variable in agent control, the symbol config is not used
  # :'agent_control.health.frequency' - the config is set by environment variable in agent control, the symbol config is not used
  # :'distributed_tracing.sampler.remote_parent_sampled' - the config is passed as a string argument in the SamplingDecision module
  # :'distributed_tracing.sampler.remote_parent_not_sampled' - the config is passed as a string argument in the SamplingDecision module
  # :'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio' - the config is interpolated in the SamplingDecision module
  # :'distributed_tracing.sampler.remote_parent_not_sampled.trace_id_ratio_based.ratio' - the config is interpolated in the SamplingDecision module
  IGNORED_KEYS = %i[
    automatic_custom_instrumentation_method_list
    agent_control.enabled
    agent_control.health.delivery_location
    agent_control.health.frequency
    distributed_tracing.sampler.remote_parent_sampled
    distributed_tracing.sampler.remote_parent_not_sampled
    distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio
    distributed_tracing.sampler.remote_parent_not_sampled.trace_id_ratio_based.ratio
  ]

  def setup
    @default_keys = ::NewRelic::Agent::Configuration::DEFAULTS.keys
  end

  def test_all_agent_config_keys_are_declared_in_default_source
    non_test_files.each do |file|
      lines_in(file).each_with_index do |line, index|
        config_match = line.match(/(?<!Security::)Agent\.config\[:['"]?([a-z\._]+)['"]?\]/)
        next unless config_match

        config_keys = config_match.captures.map do |key|
          key.delete("'").to_sym
        end

        config_keys.each do |key|
          msg = "#{file}:#{index} - Configuration key #{key} is not described in default_source.rb.\n"

          assert_includes(@default_keys, key, msg)
        end
      end
    end
  end

  def test_all_default_source_config_keys_are_used_in_the_agent
    scan_and_remove_used_entries(@default_keys, non_test_files)

    # Remove any config keys that are annotated with the 'external' setting
    # This indicates that these keys are referenced and implemented in
    # an external gem, so we don't expect any explicit references to them
    # in the core gem's code.
    #

    # Remove any of the following types of keys
    # - "external" keys: these are expected to only be leveraged by "external" code bases (Infinite Tracing, CSEC)
    # - "deprecated" keys: these are supported for a time and have their values set on new param names used in code
    # - "ignored" keys: special cased params defined by a constant above
    @default_keys.delete_if do |key_name|
      NewRelic::Agent::Configuration::DEFAULTS[key_name][:external] ||
        NewRelic::Agent::Configuration::DEFAULTS[key_name][:deprecated] ||
        IGNORED_KEYS.include?(key_name)
    end

    assert_empty @default_keys
  end

  def test_documented_all_named_instrumentation_files
    non_test_files.each do |file|
      next unless file.include?('new_relic/agent/instrumentation')

      lines_in(file).each_with_index do |line, index|
        dependency = line.match(NAMED_DEPENDENCY_PATTERN)
        if dependency
          name = dependency[1]
          disable_key = "disable_#{name}".to_sym
          instrumentation_key = "instrumentation.#{name}".to_sym

          has_disable_key = !NewRelic::Agent::Configuration::DEFAULTS[disable_key].nil?
          has_instrumentation_key = !NewRelic::Agent::Configuration::DEFAULTS[instrumentation_key].nil?

          assert has_instrumentation_key || has_disable_key,
            "#{file}:#{index + 1} - Document key `#{instrumentation_key}` found as name for instrumentation.\n"
        end
      end
    end
  end

  def non_test_files
    all_rb_files.reject { |filename| filename.include?('test.rb') }
  end
end
