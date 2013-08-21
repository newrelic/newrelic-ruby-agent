# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/default_source'

module NewRelic::Agent::Configuration
  class DefaultSourceTest < Test::Unit::TestCase
    def setup
      @default_source = DefaultSource.new
    end

    def test_default_values_have_a_public_setting
      @default_source.each do |config_setting, config_value|
        assert_not_nil config_value[:public]
      end
    end

    def test_default_values_have_types
      @default_source.each do |config_setting, config_value|
        assert_not_nil config_value[:type]
      end
    end

    def test_default_values_have_descriptions
      @default_source.each do |config_setting, config_value|
        assert_not_nil config_value[:description]
        assert config_value[:description].length > 0
      end
    end

    def test_declared_types_match_default_values
      @default_source.each do |config_setting, config_value|
        default_value = config_value[:default]
        expected_type = config_value[:type]

        value_class = get_config_value_class(default_value)

        unless value_class == Proc
          assert_equal expected_type, value_class, "Setting: #{config_setting}"
        end
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
