require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/environment_source'

module NewRelic::Agent::Configuration
  class EnvironmentSourceTest < Test::Unit::TestCase
    def test_environment_strings_are_applied
      assert_applied_string 'NRCONFIG', 'config_path'
      assert_applied_string 'NEW_RELIC_LICENSE_KEY', 'license_key'
      assert_applied_string 'NEWRELIC_LICENSE_KEY', 'license_key'
      assert_applied_string 'NEW_RELIC_APP_NAME', 'app_name'
      assert_applied_string 'NEWRELIC_APP_NAME', 'app_name'
      assert_applied_string 'NEW_RELIC_LOG', 'log_file_path'
      assert_applied_string 'NEW_RELIC_DISPATCHER', 'dispatcher'
      assert_applied_string 'NEWRELIC_DISPATCHER', 'dispatcher'
      assert_applied_string 'NEW_RELIC_FRAMEWORK', 'framework'
      assert_applied_string 'NEWRELIC_FRAMEWORK', 'framework'
    end

    def test_environment_booleans_truths_are_applied
      ENV['NEWRELIC_ENABLE'] = 'true'
      assert EnvironmentSource.new[:agent_enabled]
      ENV['NEWRELIC_ENABLE'] = 'on'
      assert EnvironmentSource.new[:agent_enabled]
      ENV['NEWRELIC_ENABLE'] = 'yes'
      assert EnvironmentSource.new[:agent_enabled]
      ENV.delete('NEWRELIC_ENABLE')
    end

    def test_environment_booleans_falsehoods_are_applied
      ENV['NEWRELIC_ENABLE'] = 'false'
      assert !EnvironmentSource.new[:agent_enabled]
      ENV['NEWRELIC_ENABLE'] = 'off'
      assert !EnvironmentSource.new[:agent_enabled]
      ENV['NEWRELIC_ENABLE'] = 'no'
      assert !EnvironmentSource.new[:agent_enabled]
      ENV.delete('NEWRELIC_ENABLE')
    end

    def assert_applied_string(env_var, config_var)
      ENV[env_var] = 'test value'
      assert_equal 'test value', EnvironmentSource.new[config_var.to_sym]
      ENV.delete(env_var)
    end
  end
end
