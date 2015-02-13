# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::Instrumentation::MiddlewareProxyTest < Minitest::Test

  def setup
    NewRelic::Agent.drop_buffered_data
  end

  def test_generator_creates_wrapped_instances
    middleware_class = Class.new

    generator = NewRelic::Agent::Instrumentation::MiddlewareProxy.for_class(middleware_class)
    wrapped_instance  = generator.new

    assert_kind_of(NewRelic::Agent::Instrumentation::MiddlewareProxy, wrapped_instance)
    assert_kind_of(middleware_class, wrapped_instance.target)
  end

  def test_generator_passes_through_initialize_args
    middleware_class = Class.new do
      attr_reader :initialize_args

      def initialize(*args)
        @initialize_args = args
      end
    end

    generator = NewRelic::Agent::Instrumentation::MiddlewareProxy.for_class(middleware_class)
    wrapped_instance = generator.new('abc', 123)

    assert_equal(['abc', 123], wrapped_instance.target.initialize_args)
  end

  def test_generator_passes_through_block_to_initialize
    middleware_class = Class.new do
      attr_reader :initialize_args

      def initialize(*args, &blk)
        @initialize_args = args
        blk.call
      end
    end

    generator = NewRelic::Agent::Instrumentation::MiddlewareProxy.for_class(middleware_class)

    block_called = false
    wrapped_instance = generator.new('abc', 123) do
      block_called = true
    end

    assert block_called
    assert_equal(['abc', 123], wrapped_instance.target.initialize_args)
  end

  def test_anonymous_class_naming
    middleware_class = Class.new
    wrapped_instance = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(middleware_class.new)

    name = wrapped_instance.transaction_options[:transaction_name]
    assert_equal("Middleware/Rack/AnonymousClass/call", name)
  end

  class BaseForAnonymous
  end

  def test_anonymous_derived_class_naming
    middleware_class = Class.new(BaseForAnonymous)
    wrapped_instance = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(middleware_class.new)

    name = wrapped_instance.transaction_options[:transaction_name]
    assert_equal("Middleware/Rack/#{BaseForAnonymous.name}/call", name)
  end

  def test_does_not_wrap_sinatra_apps
    sinatra_dummy_module = Module.new
    sinatra_dummy_class  = Class.new(Object)
    app_class            = Class.new(sinatra_dummy_class)

    with_constant_defined(:'::Sinatra', sinatra_dummy_module) do
      with_constant_defined(:'::Sinatra::Base', sinatra_dummy_class) do
        app = app_class.new

        wrapped = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(app)

        assert_same(app, wrapped)
      end
    end
  end

  def test_does_not_wrap_instrumented_middlewares
    app_class = Class.new do
      def _nr_has_middleware_tracing
        true
      end
    end

    app = app_class.new

    wrapped = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(app)

    assert_same(app, wrapped)
  end

  def test_should_wrap_non_instrumented_middlewares
    app_class = Class.new do
      def call(env)
        :yay
      end
    end

    app = app_class.new

    wrapped = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(app)

    assert_kind_of(NewRelic::Agent::Instrumentation::MiddlewareProxy, wrapped)
  end

  def test_call_should_proxy_to_target_when_in_transaction
    call_was_called = false
    call_received   = nil

    app = lambda do |env|
      call_was_called = true
      call_received   = env
      :super_duper
    end

    wrapped = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(app)
    env = {}

    ret = nil
    in_transaction do
      ret = wrapped.call(env)
    end

    assert(call_was_called)
    assert_equal(:super_duper, ret)
    assert_same(env, call_received)
  end

  def test_call_should_proxy_to_target_when_not_in_transaction
    call_was_called = false
    call_received   = nil

    app = lambda do |env|
      call_was_called = true
      call_received   = env
      :super_duper
    end

    wrapped = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(app)
    env = {}
    ret = wrapped.call(env)

    assert(call_was_called)
    assert_equal(:super_duper, ret)
    assert_same(env, call_received)
  end

  def test_should_start_transaction_if_none_is_running
    app = lambda do |env|
      :super_duper
    end

    wrapped = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(app)

    wrapped.call({})

    assert_metrics_recorded("HttpDispatcher")
  end

  def test_should_respect_force_transaction_flag
    app = lambda do |env|
      :super_duper
    end

    wrapped = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(app, true)

    in_transaction('Controller/foo', :category => :controller) do
      wrapped.call({})
    end

    assert_metrics_recorded('Controller/Rack/Proc/call')
  end

  def test_should_get_the_right_name_when_target_is_a_class
    target_class = Class.new do
      def self.name
        "GreatClass"
      end

      def self.call(env)
        :super_duper
      end
    end

    wrapped = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(target_class, true)

    wrapped.call({})

    assert_metrics_recorded('Controller/Rack/GreatClass/call')
  end

  def test_should_emit_events_once
    app = Proc.new { |env| [200, {}, ["nothing"]]}
    middleware = Proc.new { |env| app.call(env) }
    wrapped_app = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(app, true)
    wrapped_middleware = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(middleware, true)

    before_call_count = 0
    after_call_count = 0

    NewRelic::Agent.instance.events.subscribe(:before_call) { before_call_count += 1 }
    NewRelic::Agent.instance.events.subscribe(:after_call) { after_call_count += 1 }

    result = wrapped_middleware.call({})
    assert_equal 1, before_call_count
    assert_equal 1, after_call_count
  end

  def test_before_call_should_receive_rack_env_hash
    app = Proc.new { |env| [200, {}, ["nothing"]]}
    wrapped_app = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(app, true)

    original_env = {}
    env_from_before_call = nil

    NewRelic::Agent.instance.events.subscribe(:before_call) { |env| env_from_before_call = env }

    wrapped_app.call(original_env)
    assert_same original_env, env_from_before_call
  end

  def test_before_call_should_receive_rack_env_hash
    app = Proc.new { |env| [200, {}, ["nothing"]] }
    wrapped_app = NewRelic::Agent::Instrumentation::MiddlewareProxy.wrap(app, true)

    original_env = {}
    env_from_after_call = nil
    result_from_after_call = nil

    NewRelic::Agent.instance.events.subscribe(:after_call) do |env, result|
      env_from_after_call = env
      result_from_after_call = result
    end

    result = wrapped_app.call(original_env)

    assert_same original_env, env_from_after_call
    assert_same result, result_from_after_call
  end
end

