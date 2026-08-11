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
      remove_fake_gems
    end

    def test_does_not_execute_without_stackprof
      define_fake_gems(stackprof: false, protobuf: true)
      NewRelic::Agent.agent.continuous_profiling_session.expects(:maybe_start).never

      with_config(:'profiling.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          load(CONTINUOUS_PROFILER_FILE)
          DependencyDetection.detect!
        end
      end

      refute_predicate last_dependency_item, :executed
    end

    def test_does_not_execute_without_google_protobuf
      define_fake_gems(stackprof: true, protobuf: false)
      NewRelic::Agent.agent.continuous_profiling_session.expects(:maybe_start).never

      with_config(:'profiling.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          load(CONTINUOUS_PROFILER_FILE)
          DependencyDetection.detect!
        end
      end

      refute_predicate last_dependency_item, :executed
    end

    def test_does_not_execute_when_disabled_via_config
      define_fake_gems(stackprof: true, protobuf: true)
      NewRelic::Agent.agent.continuous_profiling_session.expects(:maybe_start).never

      with_config(:'profiling.enabled' => false) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          load(CONTINUOUS_PROFILER_FILE)
          DependencyDetection.detect!
        end
      end

      refute_predicate last_dependency_item, :executed
    end

    def test_does_not_execute_on_jruby
      define_fake_gems(stackprof: true, protobuf: true)
      NewRelic::Agent.agent.continuous_profiling_session.expects(:maybe_start).never

      with_config(:'profiling.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, true do
          load(CONTINUOUS_PROFILER_FILE)
          DependencyDetection.detect!
        end
      end

      refute_predicate last_dependency_item, :executed
    end

    def test_executes_when_all_conditions_are_satisfied
      define_fake_gems(stackprof: true, protobuf: true)
      NewRelic::Agent.agent.continuous_profiling_session.expects(:maybe_start)

      with_config(:'profiling.enabled' => true) do
        NewRelic::LanguageSupport.stub :jruby?, false do
          load(CONTINUOUS_PROFILER_FILE)
          DependencyDetection.detect!
        end
      end

      assert_predicate last_dependency_item, :executed
    end

    private

    def last_dependency_item
      DependencyDetection.instance_variable_get(:@items).last
    end

    def define_fake_gems(stackprof:, protobuf:)
      Object.const_set(:StackProf, Module.new) if stackprof
      Object.const_set(:Google, Module.new) if protobuf
      Google.const_set(:Protobuf, Module.new) if protobuf && defined?(Google)
    end

    def remove_fake_gems
      Object.send(:remove_const, :StackProf) if defined?(StackProf)
      Object.send(:remove_const, :Google) if defined?(Google)
    end
  end
end
