# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class TransactionTracingPerfTests < Performance::TestCase
  def klass(instrument)
    Class.new do
      def self.name
        "CustomClass#{object_id}"
      end

      def short_transaction
        method_4
      end

      def long_transaction(n)
        n.times do
          method_1
        end
      end

      def method_1
        method_2
        method_3
      end

      def method_2
      end

      def method_3
      end

      def method_4
      end

      if instrument
        include NewRelic::Agent::Instrumentation::ControllerInstrumentation
        include NewRelic::Agent::MethodTracer
        add_method_tracer :method_1
        add_method_tracer :method_2
        add_method_tracer :method_3
        add_method_tracer :method_4
        add_transaction_tracer :short_transaction
        add_transaction_tracer :long_transaction
      end

    end
  end

  def setup
    @dummy = klass(true).new
    NewRelic::Agent.manual_start(
      :developer_mode => false,
      :monitor_mode   => false
    )
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  def test_short_transactions
    measure { @dummy.short_transaction }
  end

  def test_long_transactions
    measure do
      @dummy.long_transaction(10000)
    end
  end
end
