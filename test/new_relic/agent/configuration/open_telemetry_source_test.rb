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

    def with_otel_enabled
      with_config(:'opentelemetry.enabled' => true) { yield }
    end

    def test_has_key_returns_false_when_opentelemetry_disabled
      with_environment('OTEL_SERVICE_NAME' => 'my-service') do
        source = OpenTelemetrySource.new

        with_config(:'opentelemetry.enabled' => false) do
          refute source.has_key?(:app_name)
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

      with_otel_enabled do
        refute source.has_key?(:app_name)
      end
    ensure
      ENV['OTEL_SERVICE_NAME'] = service_name if var_present
    end

    def test_has_key_returns_true_when_env_var_present_and_otel_enabled
      with_environment('OTEL_SERVICE_NAME' => 'my-service') do
        source = OpenTelemetrySource.new

        with_otel_enabled do
          assert source.has_key?(:app_name)
        end
      end
    end

    def test_source_does_not_expose_opentelemetry_enabled_key
      source = OpenTelemetrySource.new

      with_otel_enabled do
        refute source.has_key?(:'opentelemetry.enabled')
      end
    end

    def test_otel_service_name_maps_to_app_name
      with_environment('OTEL_SERVICE_NAME' => 'my-otel-app') do
        source = OpenTelemetrySource.new

        with_otel_enabled do
          assert_equal 'my-otel-app', source[:app_name]
        end
      end
    end

    def test_otel_log_level_maps_to_log_level
      with_environment('OTEL_LOG_LEVEL' => 'DEBUG') do
        source = OpenTelemetrySource.new

        with_otel_enabled do
          assert_equal 'debug', source[:log_level]
        end
      end
    end

    def test_otel_log_level_is_downcased
      %w[DEBUG INFO WARN ERROR].each do |level|
        with_environment('OTEL_LOG_LEVEL' => level) do
          source = OpenTelemetrySource.new

          with_otel_enabled do
            assert_equal level.downcase, source[:log_level]
          end
        end
      end
    end

    def test_otel_resource_attributes_maps_to_labels
      with_environment('OTEL_RESOURCE_ATTRIBUTES' => 'service.name=frontend,team=platform') do
        source = OpenTelemetrySource.new

        with_otel_enabled do
          assert_equal 'service.name:frontend;team:platform', source[:labels]
        end
      end
    end

    def test_otel_resource_attributes_single_pair
      with_environment('OTEL_RESOURCE_ATTRIBUTES' => 'env=production') do
        source = OpenTelemetrySource.new

        with_otel_enabled do
          assert_equal 'env:production', source[:labels]
        end
      end
    end

    def test_otel_bsp_max_export_batch_size_maps_to_span_events
      with_environment('OTEL_BSP_MAX_EXPORT_BATCH_SIZE' => '500') do
        source = OpenTelemetrySource.new

        with_otel_enabled do
          assert source.has_key?(:'span_events.max_samples_stored')
          assert_equal '500', source[:'span_events.max_samples_stored']
        end
      end
    end

    def test_otel_blrp_max_export_batch_size_maps_to_log_forwarding
      with_environment('OTEL_BLRP_MAX_EXPORT_BATCH_SIZE' => '2000') do
        source = OpenTelemetrySource.new

        with_otel_enabled do
          assert source.has_key?(:'application_logging.forwarding.max_samples_stored')
          assert_equal '2000', source[:'application_logging.forwarding.max_samples_stored']
        end
      end
    end

    def test_bracket_accessor_returns_nil_when_otel_disabled
      with_environment('OTEL_SERVICE_NAME' => 'lost-service') do
        source = OpenTelemetrySource.new

        with_config(:'opentelemetry.enabled' => false) do
          assert_nil source[:app_name]
        end
      end
    end

    def test_manager_includes_open_telemetry_source_in_stack
      assert_includes NewRelic::Agent.config.config_classes_for_testing, OpenTelemetrySource
    end

    def test_otel_source_is_above_default_source_in_stack
      # NewRelic::Agent.config.replace_or_add_config(DefaultSource.new)
      classes = NewRelic::Agent.config.config_classes_for_testing

      assert classes.index(OpenTelemetrySource) < classes.index(DefaultSource),
        'OpenTelemetrySource should have higher priority than DefaultSource'
    end

    def test_otel_source_is_below_environment_source_in_stack
      classes = NewRelic::Agent.config.config_classes_for_testing

      assert classes.index(EnvironmentSource) < classes.index(OpenTelemetrySource),
        'EnvironmentSource should have higher priority than OpenTelemetrySource'
    end

    def test_otel_source_is_below_yaml_source_in_stack
      NewRelic::Agent.config.replace_or_add_config(YamlSource.new('test', 'test'))
      classes = NewRelic::Agent.config.config_classes_for_testing

      assert classes.index(YamlSource) < classes.index(OpenTelemetrySource),
        'YamlSource should have higher priority than OpenTelemetrySource'
    end

    def test_otel_service_name_used_via_config_when_otel_enabled
      with_environment('OTEL_SERVICE_NAME' => 'test-service') do
        # Reinitialize so OpenTelemetrySource picks up the env var
        NewRelic::Agent.config.replace_or_add_config(OpenTelemetrySource.new)

        with_otel_enabled do
          assert_equal ['test-service'], NewRelic::Agent.config[:app_name]
        end
      end
    end

    def test_nr_env_var_takes_precedence_over_otel_env_var
      with_environment('OTEL_SERVICE_NAME' => 'from_otel') do
        with_environment('NEW_RELIC_APP_NAME' => 'from_nr') do
          # Reinitialize both sources to pick up both env vars
          NewRelic::Agent.config.replace_or_add_config(EnvironmentSource.new)
          NewRelic::Agent.config.replace_or_add_config(OpenTelemetrySource.new)

          with_otel_enabled do
            assert_equal ['from_nr'], NewRelic::Agent.config[:app_name]
          end
        end
      end
    end
  end
end
