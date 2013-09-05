# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/default_source'

module NewRelic::Agent::Configuration
  class DefaultSourceTest < Test::Unit::TestCase
    def setup
      @default_source = DefaultSource.new
      @defaults = ::NewRelic::Agent::Configuration::DEFAULTS
    end

    def test_default_values_have_a_public_setting
      @defaults.each do |config_setting, config_value|
        assert_not_nil config_value[:public], "Config setting: #{config_setting}"
      end
    end

    def test_default_values_have_types
      @defaults.each do |config_setting, config_value|
        assert_not_nil config_value[:type], "Config setting: #{config_setting}"
      end
    end

    def test_default_values_have_descriptions
      @defaults.each do |config_setting, config_value|
        assert_not_nil config_value[:description]
        assert config_value[:description].length > 0, "Config setting: #{config_setting}"
      end
    end

    def test_declared_types_match_default_values
      NewRelic::Control.instance.local_env.stubs(:discovered_dispatcher).returns(:unicorn)

      @default_source.keys.each do |key|
        default_value_class = get_config_value_class(fetch_config_value(key))
        assert_equal @defaults[key][:type], default_value_class, "Config setting #{key} does not have the correct type."
      end
    end

    def test_default_values_maps_keys_to_their_default_values
      default_values = @default_source.default_values

      @defaults.each do |key, value|
        assert_equal value[:default], default_values[key]
      end
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
