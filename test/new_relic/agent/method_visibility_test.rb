# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class MethodVisibilityTest < Minitest::Test

  class InstrumentedClass
    include NewRelic::Agent::MethodTracer
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation

    def public_method!
    end

    def public_transaction!
    end

    private
    def private_method!
    end

    def private_transaction!
    end

    protected
    def protected_method!
    end

    def protected_transaction!
    end

    add_method_tracer :public_method!
    add_method_tracer :private_method!
    add_method_tracer :protected_method!

    add_transaction_tracer :public_transaction!
    add_transaction_tracer :private_transaction!
    add_transaction_tracer :protected_transaction!
  end


  class ObjectWithInstrumentation
    include NewRelic::Agent::MethodTracer
    include NewRelic::Agent::Instrumentation::ControllerInstrumentation
  end

  class ObjectWithTracers < ObjectWithInstrumentation
    private
    def a_private_method
    end
    def a_private_transaction
    end
    protected
    def a_protected_method
    end
    def a_protected_transaction
    end

    add_method_tracer :a_private_method
    add_method_tracer :a_protected_method
    add_transaction_tracer :a_private_transaction
    add_transaction_tracer :a_protected_transaction
  end


  def setup
    @instance = InstrumentedClass.new
  end

  %w| public private protected |.each do |visibility|
    define_method "test_should_preserve_visibility_of_#{visibility}_traced_method" do
      assert @instance.send("#{visibility}_methods").map{|s|s.to_sym}.include?(:"#{visibility}_method!"), "Method #{visibility}_method should be #{visibility}"
    end

    define_method "test_should_preserve_visibility_of_#{visibility}_traced_transaction" do
      assert @instance.send("#{visibility}_methods").map{|s|s.to_sym}.include?(:"#{visibility}_transaction!"), "Transcation #{visibility}_transaction should be #{visibility}"
    end
  end

  def test_tracing_non_public_methods_doesnt_add_public_methods
    assert_equal [], ObjectWithTracers.public_instance_methods - ObjectWithInstrumentation.public_instance_methods
  end

  # FIXME: Currently including MethodTracer and ControllerInstrumentation
  # adds a bunch of public methods to the class.  It probably shouldn't do this.
  #def test_instrumentation_doesnt_add_any_public_methods
  #  assert_equal [], ObjectWithInstrumentation.public_instance_methods - Object.public_instance_methods
  #end
  #

end
