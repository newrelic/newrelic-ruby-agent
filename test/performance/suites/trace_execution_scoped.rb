# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class TestClass
  def method_1
    trace_execution_scoped(%w[a b]) do
      'hi'
    end
  end
end

class TraceExecutionScopedTests < Performance::TestCase
  ITERATIONS = 20_000

  def setup
    @test_class = TestClass.new
    TestClass.instance_eval('include NewRelic::Agent::MethodTracer')
    require 'new_relic/agent/method_tracer'
  end

  def test_trace_execution_scoped
    measure(ITERATIONS) { @test_class.method_1 }
  end

  def test_trace_execution_scoped_in_a_transaction
    measure(ITERATIONS) do
      in_transaction do
        @test_class.method_1
      end
    end
  end
end
