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
      end

      def teardown
        NewRelic::Agent.config.reset_to_defaults
      end

      def test_does_not_run_requires_without_opentelemetry_api_gem
        assert NewRelic::Agent::OpenTelemetryBridge.new
      end

      def test_does_not_install_if_overall_flag_off_but_traces_on
        with_config(:'opentelemetry.enabled' => false, :'opentelemetry.traces.enabled' => true) do
          NewRelic::Agent::OpenTelemetryBridge.stub(:install, -> { raise BridgeInstallationError.new }) do
            refute_raises(BridgeInstallationError) { NewRelic::Agent::OpenTelemetryBridge.new }
          end
        end
      end

      def test_does_not_install_if_overall_flag_on_but_traces_off
        with_config(:'opentelemetry.enabled' => true, :'opentelemetry.traces.enabled' => false) do
          NewRelic::Agent::OpenTelemetryBridge.stub(:install, -> { raise BridgeInstallationError.new }) do
            refute_raises(BridgeInstallationError) { NewRelic::Agent::OpenTelemetryBridge.new }
          end
        end
      end

      def test_does_not_run_requires_without_config
        with_config(:'opentelemetry.enabled' => false) do
          Object.stub_const(:OpenTelemetry, nil) do # pretend like the opentelemetry-api gem is installed
            assert NewRelic::Agent::OpenTelemetryBridge.new
          end
        end
      end

      def test_installs_bridge_when_configured
        Object.stub_const(:OpenTelemetry, nil) do # pretend like the opentelemetry-api gem is installed
          NewRelic::Agent::OpenTelemetryBridge.stub(:install, -> { raise BridgeInstallationError.new }) do
            assert_raises(BridgeInstallationError) { NewRelic::Agent::OpenTelemetryBridge.new }
          end
        end
      end

      def test_adds_supportability_metric_when_opentelemetry_enabled
        Object.stub_const(:OpenTelemetry, nil) do # pretend like the opentelemetry-api gem is installed
          NewRelic::Agent::OpenTelemetryBridge.stub(:install, -> { nil }) do
            NewRelic::Agent::OpenTelemetryBridge.new

            assert_metrics_recorded('Supportability/Tracing/Ruby/OpenTelemetryBridge/enabled')
          end
        end
      end

      # def test_adds_supportability_metric_when_opentelemetry_disabled
      #   with_config(:'opentelemetry.enabled' => false) do
      #     NewRelic::Agent::OpenTelemetryBridge.new

      #     assert_metrics_recorded('Supportability/Tracing/Ruby/OpenTelemetryBridge/disabled')
      #   end
      # end

      def test_install_instrumentation_returns_early_when_registry_not_defined
        otel_module = Module.new

        Object.stub_const(:OpenTelemetry, otel_module) do
          # Should not raise an error even though registry doesn't exist
          assert_nil NewRelic::Agent::OpenTelemetryBridge.send(:install_instrumentation)
        end
      end

      def test_install_instrumentation_filters_excluded_instrumentation
        with_config(
          :'opentelemetry.traces.exclude' => 'OpenTelemetry::Instrumentation::Redis,OpenTelemetry::Instrumentation::PG',
          :'opentelemetry.traces.include' => ''
        ) do
          mock_registry = Minitest::Mock.new
          mock_lock = Mutex.new

          # Create simple objects that respond to to_s
          redis_inst = Object.new
          pg_inst = Object.new
          rails_inst = Object.new
          redis_inst.define_singleton_method(:to_s) { 'OpenTelemetry::Instrumentation::Redis' }
          pg_inst.define_singleton_method(:to_s) { 'OpenTelemetry::Instrumentation::PG' }
          rails_inst.define_singleton_method(:to_s) { 'OpenTelemetry::Instrumentation::Rails' }

          mock_instrumentation = [redis_inst, pg_inst, rails_inst]

          mock_registry.expect(:instance_variable_get, mock_lock, [:@lock])
          mock_registry.expect(:instance_variable_get, mock_instrumentation, [:@instrumentation])
          mock_registry.expect(:instance_variable_set, nil) do |var, value|
            assert_equal :@instrumentation, var
            assert_equal 1, value.length
            assert_equal 'OpenTelemetry::Instrumentation::Rails', value.first.to_s
            true
          end
          mock_registry.expect(:install_all, nil)

          otel_module = Module.new
          instrumentation_module = Module.new
          registry_class = Class.new

          instrumentation_module.define_singleton_method(:registry) { mock_registry }

          Object.stub_const(:OpenTelemetry, otel_module) do
            otel_module.stub_const(:Instrumentation, instrumentation_module) do
              instrumentation_module.stub_const(:Registry, registry_class) do
                NewRelic::Agent::OpenTelemetryBridge.send(:install_instrumentation)
              end
            end
          end

          mock_registry.verify
        end
      end

      def test_install_instrumentation_handles_whitespace_in_config
        with_config(
          :'opentelemetry.traces.exclude' => ' OpenTelemetry::Instrumentation::Redis , OpenTelemetry::Instrumentation::PG ',
          :'opentelemetry.traces.include' => ''
        ) do
          mock_registry = Minitest::Mock.new
          mock_lock = Mutex.new

          redis_inst = Object.new
          pg_inst = Object.new
          redis_inst.define_singleton_method(:to_s) { 'OpenTelemetry::Instrumentation::Redis' }
          pg_inst.define_singleton_method(:to_s) { 'OpenTelemetry::Instrumentation::PG' }

          mock_instrumentation = [redis_inst, pg_inst]

          mock_registry.expect(:instance_variable_get, mock_lock, [:@lock])
          mock_registry.expect(:instance_variable_get, mock_instrumentation, [:@instrumentation])
          mock_registry.expect(:instance_variable_set, nil) do |var, value|
            assert_equal :@instrumentation, var
            assert_equal 0, value.length, 'Should filter both items despite whitespace'
            true
          end
          mock_registry.expect(:install_all, nil)

          otel_module = Module.new
          instrumentation_module = Module.new
          registry_class = Class.new

          instrumentation_module.define_singleton_method(:registry) { mock_registry }

          Object.stub_const(:OpenTelemetry, otel_module) do
            otel_module.stub_const(:Instrumentation, instrumentation_module) do
              instrumentation_module.stub_const(:Registry, registry_class) do
                NewRelic::Agent::OpenTelemetryBridge.send(:install_instrumentation)
              end
            end
          end

          mock_registry.verify
        end
      end

      def test_install_instrumentation_include_overrides_exclude
        with_config(
          :'opentelemetry.traces.exclude' => 'OpenTelemetry::Instrumentation::Redis,OpenTelemetry::Instrumentation::PG',
          :'opentelemetry.traces.include' => 'OpenTelemetry::Instrumentation::Redis'
        ) do
          mock_registry = Minitest::Mock.new
          mock_lock = Mutex.new

          redis_inst = Object.new
          pg_inst = Object.new
          rails_inst = Object.new
          redis_inst.define_singleton_method(:to_s) { 'OpenTelemetry::Instrumentation::Redis' }
          pg_inst.define_singleton_method(:to_s) { 'OpenTelemetry::Instrumentation::PG' }
          rails_inst.define_singleton_method(:to_s) { 'OpenTelemetry::Instrumentation::Rails' }

          mock_instrumentation = [redis_inst, pg_inst, rails_inst]

          mock_registry.expect(:instance_variable_get, mock_lock, [:@lock])
          mock_registry.expect(:instance_variable_get, mock_instrumentation, [:@instrumentation])
          mock_registry.expect(:instance_variable_set, nil) do |var, value|
            assert_equal :@instrumentation, var
            assert_equal 2, value.length
            assert_includes value.map(&:to_s), 'OpenTelemetry::Instrumentation::Redis'
            assert_includes value.map(&:to_s), 'OpenTelemetry::Instrumentation::Rails'
            refute_includes value.map(&:to_s), 'OpenTelemetry::Instrumentation::PG'
            true
          end
          mock_registry.expect(:install_all, nil)

          otel_module = Module.new
          instrumentation_module = Module.new
          registry_class = Class.new

          instrumentation_module.define_singleton_method(:registry) { mock_registry }

          Object.stub_const(:OpenTelemetry, otel_module) do
            otel_module.stub_const(:Instrumentation, instrumentation_module) do
              instrumentation_module.stub_const(:Registry, registry_class) do
                NewRelic::Agent::OpenTelemetryBridge.send(:install_instrumentation)
              end
            end
          end

          mock_registry.verify
        end
      end

      def test_install_instrumentation_with_empty_exclude_list
        with_config(
          :'opentelemetry.traces.exclude' => '',
          :'opentelemetry.traces.include' => ''
        ) do
          mock_registry = Minitest::Mock.new

          redis_inst = Object.new
          pg_inst = Object.new
          redis_inst.define_singleton_method(:to_s) { 'OpenTelemetry::Instrumentation::Redis' }
          pg_inst.define_singleton_method(:to_s) { 'OpenTelemetry::Instrumentation::PG' }

          mock_instrumentation = [redis_inst, pg_inst]

          # we don't add expects for the lock and instance variable changes
          # because they're skipped if we don't have anything to exclude
          mock_registry.expect(:install_all, nil)

          otel_module = Module.new
          instrumentation_module = Module.new
          registry_class = Class.new

          instrumentation_module.define_singleton_method(:registry) { mock_registry }

          Object.stub_const(:OpenTelemetry, otel_module) do
            otel_module.stub_const(:Instrumentation, instrumentation_module) do
              instrumentation_module.stub_const(:Registry, registry_class) do
                NewRelic::Agent::OpenTelemetryBridge.send(:install_instrumentation)
              end
            end
          end

          mock_registry.verify
        end
      end
    end
  end
end
