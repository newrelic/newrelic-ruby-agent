# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/configuration/open_telemetry_source'

module NewRelic::Agent::Configuration
  class OpenTelemetrySourceTest < Minitest::Test
    def teardown
      NewRelic::Agent.config.reset_to_defaults
    end

    def test_otel_env_vars_logging_lists_unknown_and_skips_known_vars
      NewRelic::Agent.stub(:logger, NewRelic::Agent::MemoryLogger.new) do
        with_environment('OTEL_TRACES_EXPORTER' => 'otlp', 'OTEL_SERVICE_NAME' => 'my-service') do
          OpenTelemetrySource.new

          found = NewRelic::Agent.logger.messages.find { |m| m[1][0].include?('OpenTelemetry configurations found') }
          level = found[0]
          msg = found[1][0]

          assert_equal :debug, level
          assert_includes msg, 'agent will ignore the following', 'Prefix for log message not found'
          assert_includes msg, 'OTEL_TRACES_EXPORTER', 'OTEL_TRACES_EXPORTER not found in message. Unmapped environment variables should be included'
          refute_includes msg, 'OTEL_SERVICE_NAME', 'OTEL_SERVICE_NAME found in message. Mapped environment variables should not be included'
        end
      end
    end

    def test_has_key_returns_false_when_env_var_absent
      var_present = ENV.key?('OTEL_SERVICE_NAME')
      if var_present
        service_name = ENV['OTEL_SERVICE_NAME']
        ENV.delete('OTEL_SERVICE_NAME')
      end

      source = OpenTelemetrySource.new

      refute source.has_key?(:app_name)
    ensure
      ENV['OTEL_SERVICE_NAME'] = service_name if var_present
    end

    def test_has_key_returns_true_when_env_var_present_and_otel_enabled
      with_environment('OTEL_SERVICE_NAME' => 'my-service') do
        source = OpenTelemetrySource.new

        assert source.has_key?(:app_name)
      end
    end

    def test_source_does_not_expose_opentelemetry_enabled_key
      source = OpenTelemetrySource.new

      refute source.has_key?(:'opentelemetry.enabled')
    end

    def test_otel_service_name_maps_to_app_name
      with_environment('OTEL_SERVICE_NAME' => 'my-otel-app') do
        source = OpenTelemetrySource.new

        assert_equal 'my-otel-app', source[:app_name]
      end
    end

    def test_otel_sdk_disabled_false_makes_agent_enabled_true
      with_environment('OTEL_SDK_DISABLED' => 'false') do
        source = OpenTelemetrySource.new

        assert source[:agent_enabled]
      end
    end

    def test_otel_sdk_disabled_true_makes_agent_enabled_false
      with_environment('OTEL_SDK_DISABLED' => 'true') do
        source = OpenTelemetrySource.new

        refute source[:agent_enabled]
      end
    end

    def test_manager_includes_open_telemetry_source_in_stack
      assert_includes NewRelic::Agent.config.config_classes_for_testing, OpenTelemetrySource
    end

    def test_otel_source_is_below_environment_source_in_stack
      classes = NewRelic::Agent.config.config_classes_for_testing

      assert classes.index(EnvironmentSource) < classes.index(OpenTelemetrySource),
        'EnvironmentSource should have higher priority than OpenTelemetrySource'
    end

    def test_otel_source_is_above_yaml_source_in_stack
      NewRelic::Agent.config.replace_or_add_config(YamlSource.new('test', 'test'))
      classes = NewRelic::Agent.config.config_classes_for_testing

      assert classes.index(OpenTelemetrySource) < classes.index(YamlSource),
        'OpenTelemetrySource should have higher priority than YamlSource'
    end

    def test_otel_service_name_used_via_config_when_otel_enabled
      with_environment('OTEL_SERVICE_NAME' => 'test-service') do
        # Reinitialize so OpenTelemetrySource picks up the env var
        NewRelic::Agent.config.replace_or_add_config(OpenTelemetrySource.new)

        assert_equal ['test-service'], NewRelic::Agent.config[:app_name]
      end
    end

    def test_nr_env_var_takes_precedence_over_otel_env_var
      with_environment('OTEL_SERVICE_NAME' => 'from_otel') do
        with_environment('NEW_RELIC_APP_NAME' => 'from_nr') do
          # Reinitialize both sources to pick up both env vars
          NewRelic::Agent.config.replace_or_add_config(EnvironmentSource.new)
          NewRelic::Agent.config.replace_or_add_config(OpenTelemetrySource.new)

          assert_equal ['from_nr'], NewRelic::Agent.config[:app_name]
        end
      end
    end
  end
end
