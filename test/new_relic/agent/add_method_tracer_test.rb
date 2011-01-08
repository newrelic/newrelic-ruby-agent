require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
class NewRelic::Agent::AgentStartTest < Test::Unit::TestCase
  require 'new_relic/agent/method_tracer'
  include NewRelic::Agent::MethodTracer::ClassMethods::AddMethodTracer

  def test_false
    assert false, "this needs more tests"
  end
end
