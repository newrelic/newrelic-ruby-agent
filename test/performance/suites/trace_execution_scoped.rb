# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class TestClass
  def method_1
    trace_execution_scoped(['a', 'b']) do
    end
  end

  def method_2
    callback = Proc.new { ['c', 'd'] }
    trace_execution_scoped(['a', 'b'], { :additional_metrics_callback => callback }) do
    end
  end
end

class TraceExecutionScopedTests < Performance::TestCase
  def setup
    @test_class = TestClass.new
    TestClass.instance_eval('include NewRelic::Agent::MethodTracer')
    require 'new_relic/agent/method_tracer'
  end

  def test_without_callback
    measure { @test_class.method_1 }
  end

  def test_with_callback
    measure { @test_class.method_2 }
  end
end
