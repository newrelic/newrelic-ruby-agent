require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

require 'set'
class NewRelic::Agent::AgentStartTest < Test::Unit::TestCase
  require 'new_relic/agent/method_tracer'
  include NewRelic::Agent::MethodTracer::ClassMethods::AddMethodTracer

  def test_validate_options_nonhash
    assert_raise(TypeError) do
      validate_options([])
    end
  end

  def test_validate_options_defaults
    self.expects(:check_for_illegal_keys!)
    self.expects(:set_deduct_call_time_based_on_metric).with(DEFAULT_SETTINGS)
    validate_options({})
  end

  def test_validate_options_override
    opts = {:push_scope => false, :metric => false, :force => true}
    self.expects(:check_for_illegal_keys!)
    val = validate_options(opts)
    assert val.is_a?(Hash)
    assert (val[:push_scope] == false), val.inspect
    assert (val[:metric] == false), val.inspect
    assert (val[:force] == true), val.inspect
  end

  def test_set_deduct_call_time_based_on_metric_positive
    opts = {:metric => true}
    val = set_deduct_call_time_based_on_metric(opts)
    assert val.is_a?(Hash)
    assert val[:deduct_call_time_from_parent]
  end

  def test_set_deduct_call_time_based_on_metric_negative
    opts = {:metric => false}
    val = set_deduct_call_time_based_on_metric(opts)
    assert val.is_a?(Hash)
    assert !val[:deduct_call_time_from_parent]
  end

  def test_set_deduct_call_time_based_on_metric_non_nil
    opts = {:deduct_call_time_from_parent => true, :metric => false}
    val = set_deduct_call_time_based_on_metric(opts)
    assert val.is_a?(Hash)
    assert val[:deduct_call_time_from_parent]
  end

  def test_set_deduct_call_time_based_on_metric_opposite
    opts = {:deduct_call_time_from_parent => false, :metric => true}
    val = set_deduct_call_time_based_on_metric(opts)
    assert val.is_a?(Hash)
    assert !val[:deduct_call_time_from_parent]
  end

  def test_unrecognized_keys_positive
    assert_equal [:unrecognized, :keys].to_set, unrecognized_keys([:hello, :world], {:unrecognized => nil, :keys => nil}).to_set
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
    assert_raise(RuntimeError) do
      check_for_illegal_keys!({:unknown_key => nil})
    end
  end

  def test_check_for_illegal_keys_negative
    test_keys = Hash[ALLOWED_KEYS.map {|x| [x, nil]}]
    check_for_illegal_keys!(test_keys)
  end
end
