# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/rack/agent_hooks'

class AgentHooksTest < Test::Unit::TestCase

  def setup
    @app = stub_everything
    @hooks = NewRelic::Rack::AgentHooks.new(@app)
    @env = {:env => "env"}

    NewRelic::Agent.instance.events.stubs(:notify)
  end

  def test_before_call
    NewRelic::Agent.instance.events.expects(:notify).with(:before_call, @env)

    @hooks.call(@env)
  end

  def test_after_call
    result = stub
    @app.stubs(:call).returns(result)

    NewRelic::Agent.instance.events.expects(:notify).with(:after_call, @env, result)

    @hooks.call(@env)
  end

end

