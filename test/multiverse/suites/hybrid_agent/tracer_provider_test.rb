# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class TracerProviderTest < Minitest::Test
          def setup
            @tracer_provider = NewRelic::Agent::OpenTelemetry::Trace::TracerProvider.new
          end

          def teardown
            NewRelic::Agent.config.reset_to_defaults
          end

          def test_tracer_returns_a_tracer
            assert @tracer_provider.tracer('test_tracer').is_a?(NewRelic::Agent::OpenTelemetry::Trace::Tracer)
          end

          def test_tracer_returns_a_tracer_with_name_and_version
            tracer = @tracer_provider.tracer('newrelic_rpm', '1.2.3')

            assert_equal 'newrelic_rpm', tracer.instance_variable_get(:@name)
            assert_equal '1.2.3', tracer.instance_variable_get(:@version)
          end

          def test_tracer_caches_tracers_in_registry
            tracer1 = @tracer_provider.tracer('my_tracer', '1.0.0')
            tracer2 = @tracer_provider.tracer('my_tracer', '1.0.0')

            assert_same tracer1, tracer2, 'Expected the same tracer instance to be returned from the registry'
          end

          def test_tracer_creates_different_tracers_for_different_names
            tracer1 = @tracer_provider.tracer('tracer_a', '1.0.0')
            tracer2 = @tracer_provider.tracer('tracer_b', '1.0.0')

            refute_same tracer1, tracer2, 'Expected different tracer instances for different names'
          end

          def test_tracer_creates_different_tracers_for_different_versions
            tracer1 = @tracer_provider.tracer('my_tracer', '1.0.0')
            tracer2 = @tracer_provider.tracer('my_tracer', '2.0.0')

            refute_same tracer1, tracer2, 'Expected different tracer instances for different versions'
          end

          def test_tracer_returns_noop_tracer_for_excluded_tracer
            with_config(:'opentelemetry.traces.exclude' => 'ExcludedTracer') do
              tracer = @tracer_provider.tracer('ExcludedTracer')

              assert_instance_of ::OpenTelemetry::Trace::Tracer, tracer
              refute_instance_of NewRelic::Agent::OpenTelemetry::Trace::Tracer, tracer
            end
          end

          def test_tracer_returns_noop_tracer_for_multiple_excluded_tracers
            with_config(:'opentelemetry.traces.exclude' => 'TracerA,TracerB,TracerC') do
              tracer_a = @tracer_provider.tracer('TracerA')
              tracer_b = @tracer_provider.tracer('TracerB')
              tracer_c = @tracer_provider.tracer('TracerC')

              assert_instance_of ::OpenTelemetry::Trace::Tracer, tracer_a
              assert_instance_of ::OpenTelemetry::Trace::Tracer, tracer_b
              assert_instance_of ::OpenTelemetry::Trace::Tracer, tracer_c
            end
          end

          def test_tracer_returns_nr_tracer_for_non_excluded_tracer
            with_config(:'opentelemetry.traces.exclude' => 'ExcludedTracer') do
              tracer = @tracer_provider.tracer('IncludedTracer')

              assert_instance_of NewRelic::Agent::OpenTelemetry::Trace::Tracer, tracer
            end
          end

          def test_configured_exclude_has_priority_over_configured_include
            with_config(
              :'opentelemetry.traces.exclude' => 'TracerA,TracerB',
              :'opentelemetry.traces.include' => 'TracerA'
            ) do
              excluded_tracers = @tracer_provider.excluded_tracers

              assert_includes excluded_tracers, 'TracerA', 'TracerA should be excluded even when in include list (configured exclude has priority)'
              assert_includes excluded_tracers, 'TracerB', 'TracerB should still be excluded'
            end
          end

          def test_configured_exclude_blocks_tracer_even_when_in_include_list
            with_config(
              :'opentelemetry.traces.exclude' => 'MyTracer',
              :'opentelemetry.traces.include' => 'MyTracer'
            ) do
              tracer = @tracer_provider.tracer('MyTracer')

              assert_instance_of ::OpenTelemetry::Trace::Tracer, tracer
              refute_instance_of NewRelic::Agent::OpenTelemetry::Trace::Tracer, tracer
            end
          end

          def test_default_excludes_are_applied_when_no_config
            with_config(
              :'opentelemetry.traces.exclude' => '',
              :'opentelemetry.traces.include' => ''
            ) do
              excluded_tracers = @tracer_provider.excluded_tracers

              assert_includes excluded_tracers, 'elasticsearch-api', 'elasticsearch-api should be in default excludes'
              assert_includes excluded_tracers, 'dalli', 'dalli should be in default excludes'
            end
          end

          def test_configured_include_overrides_default_exclude
            with_config(
              :'opentelemetry.traces.exclude' => '',
              :'opentelemetry.traces.include' => 'elasticsearch-api'
            ) do
              excluded_tracers = @tracer_provider.excluded_tracers

              refute_includes excluded_tracers, 'elasticsearch-api', 'elasticsearch-api should not be excluded when in include list (overrides default)'
              assert_includes excluded_tracers, 'dalli', 'dalli should still be excluded by default'
            end
          end

          def test_configured_include_allows_default_excluded_tracer
            with_config(
              :'opentelemetry.traces.exclude' => '',
              :'opentelemetry.traces.include' => 'dalli'
            ) do
              tracer = @tracer_provider.tracer('dalli')

              assert_instance_of NewRelic::Agent::OpenTelemetry::Trace::Tracer, tracer
            end
          end

          def test_configured_exclude_combined_with_default_excludes
            with_config(
              :'opentelemetry.traces.exclude' => 'MyTracer',
              :'opentelemetry.traces.include' => 'elasticsearch-api'
            ) do
              excluded_tracers = @tracer_provider.excluded_tracers

              assert_includes excluded_tracers, 'MyTracer', 'MyTracer should be excluded (configured exclude)'
              refute_includes excluded_tracers, 'elasticsearch-api', 'elasticsearch-api should not be excluded (configured include overrides default)'
              assert_includes excluded_tracers, 'dalli', 'dalli should be excluded (default exclude)'
            end
          end

          def test_excluded_tracers_memoizes_result
            with_config(
              :'opentelemetry.traces.exclude' => 'TracerA',
              :'opentelemetry.traces.include' => ''
            ) do
              result1 = @tracer_provider.excluded_tracers
              result2 = @tracer_provider.excluded_tracers

              assert_same result1, result2, 'Expected excluded_tracers to be memoized'
            end
          end

          def test_tracer_logs_warning_when_called_with_empty_name
            NewRelic::Agent.logger.expects(:warn).with(includes('called without providing a tracer name'))

            with_config(:'opentelemetry.traces.exclude' => '') do
              @tracer_provider.tracer('')
            end
          end

          def test_tracer_does_not_log_warning_with_valid_name
            NewRelic::Agent.logger.expects(:warn).never

            with_config(:'opentelemetry.traces.exclude' => '') do
              @tracer_provider.tracer('valid_tracer_name')
            end
          end

          def test_tracer_is_thread_safe
            tracers = []
            threads = []

            10.times do |i|
              threads << Thread.new do
                tracers << @tracer_provider.tracer('concurrent_tracer', '1.0.0')
              end
            end

            threads.each(&:join)

            unique_tracers = tracers.uniq

            assert_equal 1, unique_tracers.size, 'Expected all threads to receive the same tracer instance'
          end
        end
      end
    end
  end
end
