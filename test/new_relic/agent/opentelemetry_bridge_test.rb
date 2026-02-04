# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/opentelemetry_bridge'

module NewRelic
  module Agent
    class OpenTelemetryBridgeTest < Minitest::Test
      class BridgeInstallationError < StandardError; end

      def setup
        @config = {
          :'opentelemetry.enabled' => true,
          :'opentelemetry.traces.enabled' => true
        }
        NewRelic::Agent.config.add_config_for_testing(@config)
        @events = NewRelic::Agent::EventListener.new
      end

      def teardown
        NewRelic::Agent.config.reset_to_defaults
      end

      def test_does_not_run_requires_without_opentelemetry_api_gem
        assert NewRelic::Agent::OpenTelemetryBridge.new(@events)
      end

      def test_does_not_install_if_overall_flag_off_but_traces_on
        with_config(:'opentelemetry.enabled' => false, :'opentelemetry.traces.enabled' => true) do
          NewRelic::Agent::OpenTelemetryBridge.stub(:install, -> { raise BridgeInstallationError.new }) do
            refute_raises(BridgeInstallationError) { NewRelic::Agent::OpenTelemetryBridge.new(@events) }
          end
        end
      end

      def test_does_not_install_if_overall_flag_on_but_traces_off
        with_config(:'opentelemetry.enabled' => true, :'opentelemetry.traces.enabled' => false) do
          NewRelic::Agent::OpenTelemetryBridge.stub(:install, -> { raise BridgeInstallationError.new }) do
            refute_raises(BridgeInstallationError) { NewRelic::Agent::OpenTelemetryBridge.new(@events) }
          end
        end
      end

      def test_does_not_run_requires_without_config
        with_config(:'opentelemetry.enabled' => false) do
          Object.stub_const(:OpenTelemetry, nil) do # pretend like the opentelemetry-api gem is installed
            assert NewRelic::Agent::OpenTelemetryBridge.new(@events)
          end
        end
      end

      def test_installs_bridge_when_configured
        Object.stub_const(:OpenTelemetry, nil) do # pretend like the opentelemetry-api gem is installed
          NewRelic::Agent::OpenTelemetryBridge.stub(:install, -> { raise BridgeInstallationError.new }) do
            assert_raises(BridgeInstallationError) { NewRelic::Agent::OpenTelemetryBridge.new(@events) }
          end
        end
      end

      def test_adds_supportability_metric_when_opentelemetry_enabled
        Object.stub_const(:OpenTelemetry, nil) do # pretend like the opentelemetry-api gem is installed
          NewRelic::Agent::OpenTelemetryBridge.stub(:install, -> { nil }) do
            NewRelic::Agent::OpenTelemetryBridge.new(@events)
            @events.notify(:initial_configuration_complete)

            assert_metrics_recorded('Supportability/Tracing/Ruby/OpenTelemetryBridge/enabled')
          end
        end
      end

      def test_adds_supportability_metric_when_opentelemetry_disabled
        with_config(:'opentelemetry.enabled' => false) do
          NewRelic::Agent::OpenTelemetryBridge.new(@events)
          @events.notify(:initial_configuration_complete)

          assert_metrics_recorded('Supportability/Tracing/Ruby/OpenTelemetryBridge/disabled')
        end
      end
    end
  end
end
