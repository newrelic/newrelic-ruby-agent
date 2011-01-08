require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
class NewRelic::Agent::AgentStartTest < Test::Unit::TestCase
  require 'new_relic/agent/method_tracer'
  include NewRelic::Agent::MethodTracer::ClassMethods::AddMethodTracer

  def test_validate_options
    assert false, "this needs more tests"
  end

  def test_unrecognized_keys_positive
    assert_equal [:unrecognized, :keys], unrecognized_keys([:hello, :world], {:unrecognized => nil, :keys => nil})
  end

  def test_unrecognized_keys_negative
    assert_equal [], unrecognized_keys([:hello, :world], {:hello => nil, :world => nil})
  end

  def test_any_unrecognized_keys_positive
    assert any_unrecognized_keys?([:one], {:one => nil, :two => nil})
  end

  def test_any_unrecognized_keys_negative
    assert !any_unrecognized_keys?([:one], {:one => nil})
  end

  def test_check_for_illegal_keys_positive
    assert false, "Needs more tests"
  end

  def test_check_for_illegal_keys_negative
    assert false, "Needs more tests"
  end
end
