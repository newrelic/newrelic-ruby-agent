# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/opentelemetry_bridge'

module NewRelic
  module Agent
    class OpenTelemetryBridgeTest < Minitest::Test
      class BridgeInstallationError < StandardError; end

      def test_does_not_run_requires_without_opentelemetry_api_gem
        with_config(:'opentelemetry_bridge.enabled' => true) do
          assert NewRelic::Agent::OpenTelemetryBridge.new
        end
      end

      def test_does_not_run_requires_without_config
        with_config(:'opentelemetry_bridge.enabled' => false) do
          Object.stub_const(:OpenTelemetry, nil) do
            assert NewRelic::Agent::OpenTelemetryBridge.new
          end
        end
      end

      def test_installs_bridge_when_configured
        with_config(:'opentelemetry_bridge.enabled' => true) do
          Object.stub_const(:OpenTelemetry, nil) do
            NewRelic::Agent::OpenTelemetryBridge.stub(:install, -> { raise BridgeInstallationError.new }) do
              assert_raises(BridgeInstallationError) { NewRelic::Agent::OpenTelemetryBridge.new }
            end
          end
        end
      end
    end
  end
end
