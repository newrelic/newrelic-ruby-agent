# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent::Instrumentation
  class ContinuousProfilerInstrumentationTest < Minitest::Test
    CONTINUOUS_PROFILER_FILE = File.expand_path(
      '../../../../../lib/new_relic/agent/instrumentation/continuous_profiler.rb', __FILE__
    )

    def setup
      @original_items = DependencyDetection.instance_variable_get(:@items)
      DependencyDetection.instance_variable_set(:@items, [])
    end

    def teardown
      DependencyDetection.instance_variable_set(:@items, @original_items)
    end

    def test_does_not_execute_without_stackprof
      with_config(:'profiling.enabled' => true) do
        with_fake_gems(stackprof: false, protobuf: true) do
          load(CONTINUOUS_PROFILER_FILE)
          DependencyDetection.detect!
        end
      end

      refute_predicate last_dependency_item, :executed
    end

    def test_does_not_execute_without_google_protobuf
      with_config(:'profiling.enabled' => true) do
        with_fake_gems(stackprof: true, protobuf: false) do
          load(CONTINUOUS_PROFILER_FILE)
          DependencyDetection.detect!
        end
      end

      refute_predicate last_dependency_item, :executed
    end

    def test_does_not_execute_when_disabled_via_config
      with_config(:'profiling.enabled' => false) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          with_fake_gems(stackprof: true, protobuf: true) do
            load(CONTINUOUS_PROFILER_FILE)
            DependencyDetection.detect!
          end
        end
      end

      refute_predicate last_dependency_item, :executed
    end

    def test_does_not_execute_on_jruby
      with_config(:'profiling.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, true do
          with_fake_gems(stackprof: true, protobuf: true) do
            load(CONTINUOUS_PROFILER_FILE)
            DependencyDetection.detect!
          end
        end
      end

      refute_predicate last_dependency_item, :executed
    end

    def test_executes_when_all_conditions_are_satisfied
      NewRelic::Agent.agent.continuous_profiling_session.expects(:maybe_start)

      with_config(:'profiling.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          with_fake_gems(stackprof: true, protobuf: true) do
            load(CONTINUOUS_PROFILER_FILE)
            DependencyDetection.detect!
          end
        end
      end

      assert_predicate last_dependency_item, :executed
    end

    def test_name_is_set_directly_and_not_via_named
      with_config(:'profiling.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          with_fake_gems(stackprof: true, protobuf: true) do
            load(CONTINUOUS_PROFILER_FILE)
            DependencyDetection.detect!
          end
        end
      end

      assert_equal :continuous_profiler, last_dependency_item.name
    end

    def test_disable_continuous_profiler_config_key_gates_execution
      with_config(:'profiling.enabled' => true, :disable_continuous_profiler => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          with_fake_gems(stackprof: true, protobuf: true) do
            load(CONTINUOUS_PROFILER_FILE)
            DependencyDetection.detect!
          end
        end
      end

      refute_predicate last_dependency_item, :executed
    end

    private

    def last_dependency_item
      DependencyDetection.instance_variable_get(:@items).last
    end

    def with_fake_gems(stackprof:, protobuf:, &block)
      consts = {}
      consts[:StackProf] = Module.new if stackprof
      # Google itself is always stubbed; only Protobuf nesting is conditional on the arg.
      consts[:Google] = Module.new.tap { |mod| mod.const_set(:Protobuf, Module.new) if protobuf }
      Object.stub_consts(consts, &block)
    end
  end
end
