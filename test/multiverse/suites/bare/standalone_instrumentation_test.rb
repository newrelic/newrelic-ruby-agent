# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This test is based on the example code at:
# https://docs.newrelic.com/docs/ruby/ruby-custom-metric-collection#example_class
#
# See https://newrelic.atlassian.net/browse/RUBY-1116 for details on how this
# was broken previously.

require 'new_relic/agent/method_tracer'

class StandaloneInstrumentationTest < Minitest::Test
  class InstrumentedClass
    def instance_method(*args)
      args
    end

    def self.class_method(*args)
      args
    end

    include NewRelic::Agent::MethodTracer
    add_method_tracer :instance_method

    class << self
      include ::NewRelic::Agent::MethodTracer
      add_method_tracer :class_method
    end
  end

  def test_instance_method_tracers_should_not_cause_errors
    args = [1, 2, 3]
    result = InstrumentedClass.new.instance_method(*args)
    assert_equal(args, result)
  end

  def test_class_method_tracer_should_not_cause_errors
    args = [1, 2, 3]
    result = InstrumentedClass.class_method(*args)
    assert_equal(args, result)
  end
end
