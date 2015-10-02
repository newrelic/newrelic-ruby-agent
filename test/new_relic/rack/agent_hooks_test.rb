# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/rack/agent_hooks'

class AgentHooksTest < Minitest::Test

  def setup
    @app = stub_everything
    @hooks = NewRelic::Rack::AgentHooks.new(@app)
    @env = {:env => "env"}
  end

  def test_before_call
    NewRelic::Agent.instance.events.expects(:notify).with(:start_transaction)
    NewRelic::Agent.instance.events.expects(:notify).with(:before_call, @env)
    NewRelic::Agent.instance.events.stubs(:notify).with(:after_call, anything, anything)
    NewRelic::Agent.instance.events.expects(:notify).with(:transaction_finished, anything)

    @hooks.call(@env)
  end

  def test_after_call
    result = [stub, {}, stub]
    @app.stubs(:call).returns(result)

    NewRelic::Agent.instance.events.expects(:notify).with(:start_transaction)
    NewRelic::Agent.instance.events.stubs(:notify).with(:before_call, anything)
    NewRelic::Agent.instance.events.expects(:notify).with(:after_call, @env, result)
    NewRelic::Agent.instance.events.expects(:notify).with(:transaction_finished, anything)

    @hooks.call(@env)
  end

  def test_nested_agent_hooks_still_fire_only_once
    nested = NewRelic::Rack::AgentHooks.new(@hooks)

    NewRelic::Agent.instance.events.expects(:notify).times(4)
    nested.call(@env)
  end

end
