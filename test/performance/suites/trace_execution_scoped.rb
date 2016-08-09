# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class TestClass
  def method_1
    trace_execution_scoped(['a', 'b']) do
      "hi"
    end
  end
end

class TraceExecutionScopedTests < Performance::TestCase
  def setup
    @test_class = TestClass.new
    TestClass.instance_eval('include NewRelic::Agent::MethodTracer')
    require 'new_relic/agent/method_tracer'
  end

  def test_trace_execution_scoped
    measure { @test_class.method_1 }
  end

  def test_trace_execution_scoped_in_a_transaction
    measure do
      in_transaction do
        @test_class.method_1
      end
   end
  end
end
