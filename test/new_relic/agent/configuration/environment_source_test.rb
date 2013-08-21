# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/environment_source'

module NewRelic::Agent::Configuration
  class EnvironmentSourceTest < Test::Unit::TestCase

    def setup
      @original_env = {}
      @original_env.replace(ENV)
      @environment_source = EnvironmentSource.new
    end

    def teardown
      ENV.replace(@original_env)
    end

    def test_environment_strings_are_applied
      assert_applied_string 'NRCONFIG', 'config_path'
      assert_applied_string 'NEW_RELIC_LICENSE_KEY', 'license_key'
      assert_applied_string 'NEWRELIC_LICENSE_KEY', 'license_key'
      assert_applied_string 'NEW_RELIC_APP_NAME', 'app_name'
      assert_applied_string 'NEWRELIC_APP_NAME', 'app_name'
      assert_applied_string 'NEW_RELIC_HOST', 'host'
      assert_applied_string 'NEW_RELIC_PORT', 'port'
    end

    def test_environment_symbols_are_applied
      assert_applied_symbol 'NEW_RELIC_DISPATCHER', 'dispatcher'
      assert_applied_symbol 'NEWRELIC_DISPATCHER', 'dispatcher'
      assert_applied_symbol 'NEW_RELIC_FRAMEWORK', 'framework'
      assert_applied_symbol 'NEWRELIC_FRAMEWORK', 'framework'
    end

    %w| NEWRELIC_ENABLE NEWRELIC_ENABLED NEW_RELIC_ENABLE NEW_RELIC_ENABLED |.each do |var|
      define_method("test_environment_booleans_truths_are_applied_to_#{var}") do
        ENV[var] = 'true'
        assert EnvironmentSource.new[:agent_enabled]
        ENV[var] = 'on'
        assert EnvironmentSource.new[:agent_enabled]
        ENV[var] = 'yes'
        assert EnvironmentSource.new[:agent_enabled]
        ENV.delete(var)
      end

      define_method("test_environment_booleans_falsehoods_are_applied_to_#{var}") do
        ENV[var] = 'false'
        assert !EnvironmentSource.new[:agent_enabled]
        ENV[var] = 'off'
        assert !EnvironmentSource.new[:agent_enabled]
        ENV[var] = 'no'
        assert !EnvironmentSource.new[:agent_enabled]
        ENV.delete(var)
      end
    end

    %w| NEWRELIC_DISABLE_HARVEST_THREAD NEW_RELIC_DISABLE_HARVEST_THREAD |.each do |var|
      define_method("test_environment_booleans_truths_are_applied_to_#{var}") do
        ENV[var] = 'true'
        assert EnvironmentSource.new[:disable_harvest_thread]
        ENV[var] = 'on'
        assert EnvironmentSource.new[:disable_harvest_thread]
        ENV[var] = 'yes'
        assert EnvironmentSource.new[:disable_harvest_thread]
        ENV.delete(var)
      end

      define_method("test_environment_booleans_falsehoods_are_applied_to_#{var}") do
        ENV[var] = 'false'
        assert !EnvironmentSource.new[:disable_harvest_thread]
        ENV[var] = 'off'
        assert !EnvironmentSource.new[:disable_harvest_thread]
        ENV[var] = 'no'
        assert !EnvironmentSource.new[:disable_harvest_thread]
        ENV.delete(var)
      end
    end

    def test_set_log_config_from_environment
      ENV['NEW_RELIC_LOG'] = 'off/in/space.log'
      source = EnvironmentSource.new
      assert_equal 'off/in', source[:log_file_path]
      assert_equal 'space.log', source[:log_file_name]
    end

    def test_set_log_config_STDOUT_from_environment
      ENV['NEW_RELIC_LOG'] = 'STDOUT'
      source = EnvironmentSource.new
      assert_equal 'STDOUT', source[:log_file_name]
      assert_equal 'STDOUT', source[:log_file_path]
    end

    def test_set_values_from_new_relic_environment_variables
      keys = %w(NEW_RELIC_IS_RAD NEWRELIC_IS_MAGIC NR_IS_SUPER)
      keys.each { |key| ENV[key] = 'true' }

      expected_source = EnvironmentSource.new

      [:is_rad, :is_magic, :is_super].each do |key|
        assert_equal 'true', expected_source[key]
      end
    end

    def test_set_value_from_environment_variable
      ENV['NEW_RELIC_IS_RAD'] = 'super rad'
      @environment_source.set_value_from_environment_variable('NEW_RELIC_IS_RAD')
      assert_equal @environment_source[:is_rad], 'super rad'
    end

    def test_set_key_with_new_relic_prefix
      ENV['NEW_RELIC_NUKE_IT_FROM_ORBIT'] = 'true'
      assert_equal 'true', EnvironmentSource.new[:nuke_it_from_orbit]
    end

    def test_set_key_with_newrelic_prefix
      ENV['NEWRELIC_NUKE_IT_FROM_ORBIT'] = 'true'
      assert_equal 'true', EnvironmentSource.new[:nuke_it_from_orbit]
    end

    def test_set_key_with_nr_prefix
      ENV['NR_NUKE_IT_FROM_ORBIT'] = 'true'
      assert_equal 'true', EnvironmentSource.new[:nuke_it_from_orbit]
    end

    def test_does_not_set_key_without_new_relic_related_prefix
      ENV['NUKE_IT_FROM_ORBIT'] = 'true'
      assert_nil EnvironmentSource.new[:nuke_it_from_orbit]
    end

    def test_convert_environment_key_to_config_key
      result = @environment_source.convert_environment_key_to_config_key('NEW_RELIC_IS_RAD')
      assert_equal :is_rad, result
    end

    def test_collect_new_relic_environment_variable_keys
      keys = %w(NEW_RELIC_IS_RAD NEWRELIC_IS_MAGIC NR_IS_SUPER)
      keys.each { |key| ENV[key] = 'true' }

      result = @environment_source.collect_new_relic_environment_variable_keys
      assert_equal keys, result
    end

    def assert_applied_string(env_var, config_var)
      ENV[env_var] = 'test value'
      assert_equal 'test value', EnvironmentSource.new[config_var.to_sym]
      ENV.delete(env_var)
    end

    def assert_applied_symbol(env_var, config_var)
      ENV[env_var] = 'test value'
      assert_equal :'test value', EnvironmentSource.new[config_var.to_sym]
      ENV.delete(env_var)
    end

    def random_configuration_key
      DefaultSource.new.keys.sample
    end
  end
end
