# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/environment_source'

module NewRelic::Agent::Configuration
  class EnvironmentSourceTest < Minitest::Test

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
    end

    def test_environment_fixnums_are_applied
      assert_applied_fixnum 'NEW_RELIC_PORT', 'port'
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
        assert EnvironmentSource.new[:enabled]
        ENV[var] = 'on'
        assert EnvironmentSource.new[:enabled]
        ENV[var] = 'yes'
        assert EnvironmentSource.new[:enabled]
        ENV.delete(var)
      end

      define_method("test_environment_booleans_falsehoods_are_applied_to_#{var}") do
        ENV[var] = 'false'
        assert !EnvironmentSource.new[:enabled]
        ENV[var] = 'off'
        assert !EnvironmentSource.new[:enabled]
        ENV[var] = 'no'
        assert !EnvironmentSource.new[:enabled]
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
      keys = %w(NEW_RELIC_LICENSE_KEY NEWRELIC_CONFIG_PATH)
      keys.each { |key| ENV[key] = 'skywizards' }

      expected_source = EnvironmentSource.new

      [:license_key, :config_path].each do |key|
        assert_equal 'skywizards', expected_source[key]
      end
    end

    def test_set_values_from_new_relic_environment_variables_warns_unknowns
      ENV['NEWRELIC_DOESNT_USE_THIS_VALUE'] = "true"
      expects_logging(:info, includes("NEWRELIC_DOESNT_USE_THIS_VALUE"))
      @environment_source.set_values_from_new_relic_environment_variables
    end

    def test_set_values_from_new_relic_environment_variables_ignores_NEW_RELIC_LOG
      ENV['NEW_RELIC_LOG'] = "STDOUT"
      expects_no_logging(:info)
      @environment_source.set_values_from_new_relic_environment_variables
    end

    def test_set_value_from_environment_variable
      ENV['NEW_RELIC_LICENSE_KEY'] = 'super rad'
      @environment_source.set_value_from_environment_variable('NEW_RELIC_LICENSE_KEY')
      assert_equal @environment_source[:license_key], 'super rad'
    end

    def test_set_key_by_type_uses_the_default_type
      ENV['NEW_RELIC_TEST'] = 'true'
      @environment_source.set_key_by_type(:enabled, 'NEW_RELIC_TEST')
      assert_equal true, @environment_source[:enabled]
    end

    def test_set_key_with_new_relic_prefix
      assert_applied_string('NEW_RELIC_LICENSE_KEY', :license_key)
    end

    def test_set_key_with_newrelic_prefix
      assert_applied_string('NEWRELIC_LICENSE_KEY', :license_key)
    end

    def test_does_not_set_key_without_new_relic_related_prefix
      ENV['CONFIG_PATH'] = 'boom'
      refute_equal 'boom', EnvironmentSource.new[:config_path]
    end

    def test_convert_environment_key_to_config_key
      result = @environment_source.convert_environment_key_to_config_key('NEW_RELIC_IS_RAD')
      assert_equal :is_rad, result
    end

    def test_convert_environment_key_to_config_key_respects_aliases
      assert_applied_boolean('NEWRELIC_ENABLE', :enabled)
    end

    def test_convert_environment_key_to_config_key_allows_underscores_as_dots
      assert_applied_string('NEW_RELIC_AUDIT_LOG_PATH', :'audit_log.path')
    end

    def test_collect_new_relic_environment_variable_keys
      keys = %w(NEW_RELIC_IS_RAD NEWRELIC_IS_MAGIC)
      keys.each { |key| ENV[key] = 'true' }

      result = @environment_source.collect_new_relic_environment_variable_keys
      assert_equal keys, result
    end

    def test_does_not_warn_for_new_relic_env_environment_variable
      expects_no_logging(:warn)
      expects_no_logging(:info)
      with_environment('NEW_RELIC_ENV' => 'foo') do
        @environment_source.set_values_from_new_relic_environment_variables
      end
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

    def assert_applied_fixnum(env_var, config_var)
      ENV[env_var] = '3000'
      assert_equal 3000, EnvironmentSource.new[config_var.to_sym]
      ENV.delete(env_var)
    end

    def assert_applied_boolean(env_var, config_var)
      ENV[env_var] = 'true'
      assert_equal true, EnvironmentSource.new[config_var.to_sym]
      ENV.delete(env_var)
    end

  end
end
