require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/rack/agent_hooks'

class AgentHooksTest < Test::Unit::TestCase

  def setup
    @app = stub_everything
    @hooks = NewRelic::Rack::AgentHooks.new(@app)

    @called = false
    @called_with = nil

    @check_method = Proc.new do |*args|
      @called = true
      @called_with = args
    end
  end

  def test_before_call
    @hooks.subscribe(:before_call, &@check_method)
    @hooks.call({:env => "env"})

    assert_was_called
    assert_equal([{:env => "env"}], @called_with)
  end

  def test_after_call
    result = stub
    @app.stubs(:call).returns(result)

    @hooks.subscribe(:after_call, &@check_method)
    @hooks.call({:env => "env"})

    assert_was_called
    assert_equal([{:env => "env"}, result], @called_with)
  end

  def test_subscribes_through_class
    NewRelic::Rack::AgentHooks.subscribe(:after_call, &@check_method)
    @hooks.call({})

    assert_was_called
  end

  # Not sure how legitimate this case is, but covers us for multiple middlewares
  def test_subscribes_multiple_through_class
    another_hook = NewRelic::Rack::AgentHooks.new(@app)

    count = 0
    NewRelic::Rack::AgentHooks.subscribe(:after_call) { count += 1 }

    @hooks.call({})
    another_hook.call({})

    assert_equal 2, count
  end

  def assert_was_called
    assert @called, "Event wasn't called"
  end

end

