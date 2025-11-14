# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/configuration/default_source'

module NewRelic::Agent::Configuration
  class DefaultSourceTest < Minitest::Test
    def setup
      @default_source = DefaultSource.new
      @defaults = ::NewRelic::Agent::Configuration::DEFAULTS
      NewRelic::Agent.config.send(:new_cache)
    end

    def test_default_values_have_a_public_setting
      @defaults.each do |config_setting, config_value|
        refute_nil config_value[:public], "Config setting: #{config_setting}"
      end
    end

    def test_default_values_have_types
      @defaults.each do |config_setting, config_value|
        refute_nil config_value[:type], "Config setting: #{config_setting}"
      end
    end

    def test_default_values_have_descriptions
      @defaults.each do |config_setting, config_value|
        refute_nil config_value[:description]
        assert config_value[:description].length > 0, "Config setting: #{config_setting}"
      end
    end

    def test_declared_types_match_default_values
      NewRelic::Control.instance.local_env.stubs(:discovered_dispatcher).returns(:unicorn)

      @default_source.keys.each do |key|
        config_value = fetch_config_value(key)
        actual_type = get_config_value_class(config_value)
        expected_type = @defaults[key][:type]

        if @defaults[key][:allow_nil]
          assertion = (NilClass === config_value) || (expected_type === config_value)

          assert assertion, "Default value for #{key} should be NilClass or #{expected_type}, is #{actual_type}."
        else
          assertion = expected_type === config_value

          assert assertion, "Default value for #{key} should be #{expected_type}, is #{actual_type}."
        end
      end
    end

    def test_default_values_maps_keys_to_their_default_values
      default_values = @default_source.default_values

      @defaults.each do |key, value|
        if value[:default].nil?
          assert_nil default_values[key]
        else
          assert_equal value[:default], default_values[key]
        end
      end
    end

    def test_config_search_paths_include_application_root
      NewRelic::Control.instance.stubs(:root).returns('app_root')
      paths = DefaultSource.config_search_paths.call

      assert paths.any? { |p| p.include?('app_root') }
    end

    def fetch_config_value(key)
      accessor = key.to_sym
      config = @default_source

      if config.has_key?(accessor)
        if config[accessor].respond_to?(:call)
          value = config[accessor]

          while value.respond_to?(:call)
            value = config.instance_eval(&value)
          end

          return value
        else
          return config[accessor]
        end
      end
      nil
    end

    def test_transform_for_returns_something_callable
      transform = DefaultSource.transform_for(:'rules.ignore_url_regexes')

      assert_respond_to transform, :call
    end

    def test_transform_for_returns_nil_for_settings_that_do_not_have_a_transform
      assert_nil DefaultSource.transform_for(:ca_bundle_path)
    end

    def test_convert_to_list
      result = DefaultSource.convert_to_list('Foo,Bar,Baz')

      assert_equal %w[Foo Bar Baz], result
    end

    def test_convert_to_list_returns_original_argument_given_array
      result = DefaultSource.convert_to_list(['Foo'])

      assert_equal ['Foo'], result
    end

    def test_convert_to_list_raises_on_totally_wrong_object
      assert_raises(ArgumentError) do
        DefaultSource.convert_to_list(Object.new)
      end
    end

    def test_rules_ignore_converts_comma_delimited_string_to_array
      with_config(:'rules.ignore_url_regexes' => 'Foo,Bar,Baz') do
        assert_equal [/Foo/, /Bar/, /Baz/], NewRelic::Agent.config[:'rules.ignore_url_regexes']
      end
    end

    def test_config_search_paths_with_home
      with_environment('HOME' => '/home') do
        paths = DefaultSource.config_search_paths.call()

        assert_includes paths, '/home/.newrelic/newrelic.yml'
        assert_includes paths, '/home/newrelic.yml'
      end
    end

    def test_config_search_path_in_warbler
      with_environment('GEM_HOME' => '/some/path.jar!') do
        assert_includes DefaultSource.config_search_paths.call(), '/some/path.jar!/path/config/newrelic.yml'
      end
    end

    def test_agent_attribute_settings_convert_comma_delimited_strings_into_an_arrays
      types = %w[transaction_tracer. transaction_events. error_collector. browser_monitoring.]
      types << ''

      types.each do |type|
        key = "#{type}attributes.exclude".to_sym

        with_config(key => 'foo,bar,baz') do
          expected = %w[foo bar baz]
          result = NewRelic::Agent.config[key]

          message = "Expected #{key} to convert comma delimited string into array.\nExpected: #{expected.inspect}, Result: #{result.inspect}\n"

          assert_equal(expected, result, message)
        end

        key = "#{type}attributes.include".to_sym

        with_config(key => 'foo,bar,baz') do
          assert_equal %w[foo bar baz], NewRelic::Agent.config[key]
        end
      end
    end

    def test_agent_attributes_settings_with_yaml_array
      types = %w[transaction_tracer. transaction_events. error_collector. browser_monitoring.]
      types << ''

      types.each do |type|
        key = "#{type}attributes.exclude".to_sym

        with_config(key => %w[foo bar baz]) do
          expected = %w[foo bar baz]
          result = NewRelic::Agent.config[key]

          message = "Expected #{key} not to modify settings from YAML array.\nExpected: #{expected.inspect}, Result: #{result.inspect}\n"

          assert_equal expected, result, message
        end

        key = "#{type}attributes.include".to_sym

        with_config(key => 'foo,bar,baz') do
          assert_equal %w[foo bar baz], NewRelic::Agent.config[key]
        end
      end
    end

    def test_all_settings_specify_whether_they_are_allowed_from_server
      unspecified_keys = []
      bad_value_keys = []

      @defaults.each do |key, spec|
        if !spec.has_key?(:allowed_from_server)
          unspecified_keys << key
        end

        booleans = [true, false]

        if !booleans.include?(spec[:allowed_from_server])
          bad_value_keys << key
        end
      end

      assert_empty unspecified_keys, "The following keys did not specify a value for :allowed_from_server: #{unspecified_keys.join(', ')}"
      assert_empty bad_value_keys, "The following keys had incorrect :allowed_from_server values (only true or false are allowed): #{bad_value_keys.join(', ')}"
    end

    def test_host_correct_when_license_key_matches_identifier
      with_config(license_key: 'eu01xx65c637a29c3982469a3fe8d1982d002c4b') do
        assert_equal 'collector.eu01.nr-data.net', DefaultSource.host.call
      end
      with_config(license_key: 'gov01x69c637a29c3982469a3fe8d1982d002c4c') do
        assert_equal 'collector.gov01.nr-data.net', DefaultSource.host.call
      end
    end

    def test_host_correct_with_license_key_not_matching_identifer
      with_config(license_key: '08a2ad66c637a29c3982469a3fe8d1982d002c4a') do
        assert_equal 'collector.newrelic.com', DefaultSource.host.call
      end
    end

    # Tests self.instrumentation_value_from_boolean
    def test_instrumentation_logger_matches_application_logging_enabled
      with_config(:'application_logging.enabled' => true) do
        assert_equal 'auto', NewRelic::Agent.config['instrumentation.logger']
      end
    end

    def test_instrumentation_logger_matches_application_logging_disabled
      with_config(:'application_logging.enabled' => false) do
        assert_equal 'disabled', NewRelic::Agent.config['instrumentation.logger']
      end
    end

    def test_convert_to_hash_returns_hash
      result = {'key1' => 'value1', 'key2' => 'value2'}

      assert_equal(DefaultSource.convert_to_hash(result), result)
    end

    def test_convert_to_hash_with_string
      value = 'key1=value1,key2=value2'
      result = {'key1' => 'value1', 'key2' => 'value2'}

      assert_equal(DefaultSource.convert_to_hash(value), result)
    end

    def test_convert_to_hash_raises_error_with_wrong_data_type
      value = [1, 2, 3]

      assert_raises(ArgumentError) { DefaultSource.convert_to_hash(value) }
    end

    def test_allowlist_permits_valid_values
      valid_value = 'info'
      key = :'application_logging.forwarding.log_level'

      with_config(key => valid_value) do
        assert_equal valid_value, NewRelic::Agent.config[key]
      end
    end

    def test_allowlist_blocks_invalid_values_and_uses_a_default
      key = :'application_logging.forwarding.log_level'
      default = ::NewRelic::Agent::Configuration::DefaultSource.default_for(key)

      with_config(key => 'bogus') do
        assert_equal default, NewRelic::Agent.config[key]
      end
    end

    def test_automatic_custom_instrumentation_method_list_supports_an_array
      key = :automatic_custom_instrumentation_method_list
      list = %w[Beano::Roger#dodge Beano::Gnasher.gnash]
      NewRelic::Agent.stub :add_tracers_once_methods_are_defined, nil do
        with_config(key => list) do
          assert_equal list, NewRelic::Agent.config[key],
            "Expected '#{key}' to be configured with the unmodified original list"
        end
      end
    end

    def test_automatic_custom_instrumentation_method_list_supports_a_comma_delmited_string
      key = :automatic_custom_instrumentation_method_list
      list = %w[Beano::Roger#dodge Beano::Gnasher.gnash]
      NewRelic::Agent.stub :add_tracers_once_methods_are_defined, nil do
        with_config(key => list.join('                                          ,')) do
          assert_equal list, NewRelic::Agent.config[key],
            "Expected '#{key}' to be configured with the given string converted into an array"
        end
      end
    end

    def test_boolean_configs_accepts_yes_on_and_true_as_strings
      key = :'send_data_on_exit'
      config_array = %w[yes on true]

      config_array.each do |value|
        with_config(key => value) do
          assert NewRelic::Agent.config[key], "The '#{value}' value failed to evaluate as truthy!"
        end
      end
    end

    def test_boolean_configs_accepts_yes_on_and_true_as_symbols
      key = :'send_data_on_exit'
      config_array = %i[yes on true]

      config_array.each do |value|
        with_config(key => value) do
          assert NewRelic::Agent.config[key], "The '#{value}' value failed to evaluate as truthy!"
        end
      end
    end

    def test_boolean_configs_accepts_no_off_and_false_as_strings
      key = :'send_data_on_exit'

      %w[no off false].each do |value|
        with_config(key => value) do
          refute NewRelic::Agent.config[key], "The '#{value}' value failed to evaluate as falsey!"
        end
      end
    end

    def test_boolean_configs_accepts_no_off_and_false_as_strings_as_symbols
      key = :'send_data_on_exit'

      %i[no off false].each do |value|
        with_config(key => value) do
          refute NewRelic::Agent.config[key], "The '#{value}' value failed to evaluate as falsey!"
        end
      end
    end

    def test_enforce_boolean_uses_defult_on_invalid_value
      key = :'send_data_on_exit' # default value is `true`

      with_config(key => 'invalid_value') do
        assert NewRelic::Agent.config[key]
      end
    end

    def test_enforce_boolean_logs_warning_on_invalid_value
      key = :'send_data_on_exit'
      default = ::NewRelic::Agent::Configuration::DefaultSource.default_for(key)

      with_config(key => 'yikes!') do
        expects_logging(:warn, includes("Invalid value 'yikes!' for #{key}, applying default value of '#{default}'"))
      end
    end

    def test_boolean_config_evaluates_proc_configs
      key = :agent_enabled # default value is a proc

      with_config(key => 'off') do
        refute NewRelic::Agent.config[key]
      end
    end

    def get_config_value_class(value)
      type = value.class

      if type == TrueClass || type == FalseClass
        Boolean
      else
        type
      end
    end
  end
end
