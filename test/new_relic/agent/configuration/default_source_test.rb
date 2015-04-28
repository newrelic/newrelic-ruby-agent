# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/default_source'

module NewRelic::Agent::Configuration
  class DefaultSourceTest < Minitest::Test
    def setup
      @default_source = DefaultSource.new
      @defaults = ::NewRelic::Agent::Configuration::DEFAULTS
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
        actual_type = get_config_value_class(fetch_config_value(key))
        expected_type = @defaults[key][:type]

        if @defaults[key][:allow_nil]
          assert [NilClass, expected_type].include?(actual_type), "Default value for #{key} should be NilClass or #{expected_type}, is #{actual_type}."
        else
          assert_equal expected_type, actual_type, "Default value for #{key} should be #{expected_type}, is #{actual_type}."
        end
      end
    end

    def test_default_values_maps_keys_to_their_default_values
      default_values = @default_source.default_values

      @defaults.each do |key, value|
        assert_equal value[:default], default_values[key]
      end
    end

    def test_config_search_paths_include_application_root
      NewRelic::Control.instance.stubs(:root).returns('app_root')
      paths = DefaultSource.config_search_paths.call
      assert paths.any? { |p| p.include? 'app_root' }
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
      assert transform.respond_to?(:call)
    end

    def test_transform_for_returns_nil_for_settings_that_do_not_have_a_transform
      assert_nil DefaultSource.transform_for(:ca_bundle_path)
    end

    def test_convert_to_list
      result = DefaultSource.convert_to_list("Foo,Bar,Baz")
      assert_equal ['Foo', 'Bar', 'Baz'], result
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
      with_environment("HOME" => "/home") do
        paths = DefaultSource.config_search_paths.call()
        assert_includes paths, "/home/.newrelic/newrelic.yml"
        assert_includes paths, "/home/newrelic.yml"
      end
    end

    def test_config_search_path_in_warbler
      with_environment("GEM_HOME" => "/some/path.jar!") do
        assert_includes DefaultSource.config_search_paths.call(), "/some/path.jar!/path/config/newrelic.yml"
      end
    end

    def test_transaction_tracer_attributes_enabled_default
      with_config(:'transaction_tracer.capture_attributes' => :foo) do
        assert_equal :foo, NewRelic::Agent.config['transaction_tracer.attributes.enabled']
      end
    end

    def test_transaction_events_attributes_enabled_default
      with_config(:'analytics_events.capture_attributes' => :foo) do
        assert_equal :foo, NewRelic::Agent.config['transaction_events.attributes.enabled']
      end
    end

    def test_error_collector_attributes_enabled_default
      with_config(:'error_collector.capture_attributes' => :foo) do
        assert_equal :foo, NewRelic::Agent.config['error_collector.attributes.enabled']
      end
    end

    def test_browser_monitoring_attributes_enabled_default
      with_config(:'browser_monitoring.capture_attributes' => :foo) do
        assert_equal :foo, NewRelic::Agent.config['browser_monitoring.attributes.enabled']
      end
    end

    def test_agent_attribute_settings_convert_comma_delimited_strings_into_an_arrays
      types = %w(transaction_tracer. transaction_events. error_collector. browser_monitoring.)
      types << ''

      types.each do |type|
        key = "#{type}attributes.exclude".to_sym

        with_config(key => 'foo,bar,baz') do
          expected = ["foo", "bar", "baz"]
          result = NewRelic::Agent.config[key]

          message = "Expected #{key} to convert comma delimited string into array.\nExpected: #{expected.inspect}, Result: #{result.inspect}\n"
          assert expected == result, message
        end

        key = "#{type}attributes.include".to_sym

        with_config(key => 'foo,bar,baz') do
          assert_equal ["foo", "bar", "baz"], NewRelic::Agent.config[key]
        end
      end
    end

    def test_agent_attributes_settings_with_yaml_array
      types = %w(transaction_tracer. transaction_events. error_collector. browser_monitoring.)
      types << ''

      types.each do |type|
        key = "#{type}attributes.exclude".to_sym

        with_config(key => ['foo','bar','baz']) do
          expected = ["foo", "bar", "baz"]
          result = NewRelic::Agent.config[key]

          message = "Expected #{key} not to modify settings from YAML array.\nExpected: #{expected.inspect}, Result: #{result.inspect}\n"
          assert expected == result, message
        end

        key = "#{type}attributes.include".to_sym

        with_config(key => 'foo,bar,baz') do
          assert_equal ["foo", "bar", "baz"], NewRelic::Agent.config[key]
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

        if ![true, false].include?(spec[:allowed_from_server])
          bad_value_keys << key
        end
      end

      assert unspecified_keys.empty?, "The following keys did not specify a value for :allowed_from_server: #{unspecified_keys.join(', ')}"
      assert bad_value_keys.empty?, "The following keys had incorrect :allowed_from_server values (only true or false are allowed): #{bad_value_keys.join(', ')}"
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
