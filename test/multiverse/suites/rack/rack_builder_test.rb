# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'

class TestBuilderClass < ::Rack::Builder
  include NewRelic::Agent::Instrumentation::RackBuilder
end

class RackBuilderTest < Minitest::Test
  def test_dependency_detection
    instance = TestBuilderClass.new
    NewRelic::Agent::Instrumentation::RackBuilder.track_deferred_detection(instance.class)
    instance.deferred_dependency_check
    assert instance.class._nr_deferred_detection_ran
  ensure
    def TestBuilderClass
      undef :_nr_deferred_detection_ran
    end
  end

  def test_dependency_detection_does_not_run_twice
    instance = TestBuilderClass.new
    NewRelic::Agent::Instrumentation::RackBuilder.track_deferred_detection(instance.class)
    instance.class._nr_deferred_detection_ran = true
    # to ensure an early return, overwrite DependencyDetection.detect to explode
    DependencyDetection.stub :detect!, -> { raise 'kaboom' } do
      assert_nil instance.deferred_dependency_check
    end
  ensure
    def TestBuilderClass
      undef :_nr_deferred_detection_ran
    end
  end

  def test_middleware_needs_wrapping
    instance = TestBuilderClass.new
    logger = MiniTest::Mock.new
    logger.expect(:info, nil, [/^We weren't/, /^To correct this/])

    ::NewRelic::Agent::Instrumentation::RackHelpers.stub :middleware_instrumentation_enabled?, true do
      ::NewRelic::Agent::Instrumentation::MiddlewareProxy.stub :needs_wrapping?, true do
        ::NewRelic::Agent.stub :logger, logger do
          instance.check_for_late_instrumentation(nil)
        end
      end
    end
    logger.verify
  end

  def test_middleware_in_need_of_wrapping_check_skipped_unless_middleware_enabled
    instance = TestBuilderClass.new
    def instance.middleware_instrumentation_enabled?; false; end
    # verify that needs_wrapping? does not get called
    ::NewRelic::Agent::Instrumentation::MiddlewareProxy.stub :needs_wrapping?, -> { raise 'kaboom' } do
      assert_nil instance.check_for_late_instrumentation(nil)
    end
  end

  def test_middleware_in_need_of_wrapping_check_skipped_unless_need_wrapping_check_passes
    instance = TestBuilderClass.new
    def instance.middleware_instrumentation_enabled?; true; end
    ::NewRelic::Agent::Instrumentation::MiddlewareProxy.stub :needs_wrapping?, false do
      # verify that #info does not get called
      ::NewRelic::Agent.logger.stub :info, -> { raise 'kaboom' } do
        assert_nil instance.check_for_late_instrumentation(nil)
      end
    end
  end

  def test_middleware_in_need_of_wrapping_check_already_performed
    instance = TestBuilderClass.new
    instance.instance_variable_set(:@checked_for_late_instrumentation, true)
    # to ensure an early return, overwrite #middleware_instrumentation-enabled to explode
    def instance.middleware_instrumentation_enabled?; raise 'kaboom'; end
    assert_nil instance.check_for_late_instrumentation(nil)
  end

  def test_with_deferred_dependency_detection
    instance = TestBuilderClass.new
    def instance.deferred_dependency_check; end
    def instance.check_for_late_instrumentation(obj); instance_variable_set(:@object_given, obj); end
    arg = :the_arg
    instance.with_deferred_dependency_detection { arg }
    assert_equal instance.instance_variable_get(:@object_given), arg
  end

  def test_run_with_tracing
    skip 'Requires MiniTest v5+' unless MiniTest::Unit::VERSION > '5.0'

    instance = TestBuilderClass.new
    app = :the_app
    def instance.middleware_instrumentation_enabled; true; end
    ::NewRelic::Agent::Instrumentation::MiddlewareProxy.stub :wrap, true, [app, true] do
      assert instance.run_with_tracing(app) { app }
    end
  end

  def test_run_with_tracing_when_middleware_instrumentation_disabled
    instance = TestBuilderClass.new
    def instance.middleware_instrumentation_enabled?; false; end
    # to ensure an early return, overwrite MiddlewareProxy.wrap to explode
    ::NewRelic::Agent::Instrumentation::MiddlewareProxy.stub :wrap, -> { raise 'kaboom' } do
      app = :the_app
      assert_equal app, instance.run_with_tracing(app) { app }
    end
  end

  def test_use_with_tracing
    skip 'Requires MiniTest v5+' unless MiniTest::Unit::VERSION > '5.0'

    instance = TestBuilderClass.new
    def instance.middleware_instrumentation_enabled?; true; end
    middleware = 'lucky tiger cup'
    ::NewRelic::Agent::Instrumentation::MiddlewareProxy.stub :for_class, middleware, [middleware] do
      assert_equal middleware, instance.use_with_tracing(middleware) { middleware }
    end
  end

  def test_use_with_tracing_skipped_if_no_middleware_class
    instance = TestBuilderClass.new
    # ensure that middleware_instrumentation_enabled is not called
    def instance.middleware_instrumentation_enabled?; raise 'kaboom'; end
    assert_nil instance.use_with_tracing(nil) {}
  end

  def test_use_with_tracing_skipped_unless_middleware_instrumentation_enabled
    instance = TestBuilderClass.new
    def instance.middleware_instrumentation_enabled?; false; end
    middleware = :a_bit_of_strawberry_stuck_on_the_far_end_of_the_straw
    assert_nil instance.use_with_tracing(middleware) {}
  end

  def test_generate_traced_map
    skip 'Requires MiniTest v5+' unless MiniTest::Unit::VERSION > '5.0'

    url = :url
    handler = 'handler'
    map = {url => handler}
    ::NewRelic::Agent::Instrumentation::MiddlewareProxy.stub :wrap, handler.reverse, [handler, true] do
      traced_map = ::NewRelic::Agent::Instrumentation::RackURLMap.generate_traced_map(map)
      assert_equal({url => handler.reverse}, traced_map)
    end
  end
end
