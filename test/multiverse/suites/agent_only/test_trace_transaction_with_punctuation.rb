
require 'test/unit'
require 'newrelic_rpm'
require 'new_relic/agent/instrumentation/controller_instrumentation'


class TransactionInterrobangTest < Test::Unit::TestCase
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation

  def interrogate?
    "say what?"
  end

  def mutate!
    "oh yeah!"
  end

  add_transaction_tracer :interrogate?
  add_transaction_tracer :mutate!

  def test_alias_method_ending_in_question_mark
    assert_respond_to self,:interrogate?
    assert_respond_to self, :interrogate_with_newrelic_transaction_trace?
    assert_equal "say what?", interrogate?
  end

  def test_aliase_method_ending_in_exclamation_makr
    assert_respond_to self,:mutate!
    assert_respond_to self, :mutate_with_newrelic_transaction_trace!
    assert_equal "oh yeah!",mutate!
  end
end
