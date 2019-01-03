# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class TransactionTracingPerfTests < Performance::TestCase
  FAILURE_MESSAGE = "O_o"

  BOO = "boo"
  HOO = "hoo"
  OH  = "oh"
  NO  = "no"

  def klass(instrument)
    Class.new do
      def self.name
        "CustomClass#{object_id}"
      end

      def short_transaction
        method_4
      end

      def transaction_with_attributes
        method_4
        NewRelic::Agent.add_custom_attributes(BOO => HOO, OH => NO)
      end

      def long_transaction(n)
        n.times do
          method_1
        end
      end


      def failure
        raise FAILURE_MESSAGE
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
        add_transaction_tracer :transaction_with_attributes
        add_transaction_tracer :failure
      end

    end
  end

  def setup
    @dummy = klass(true).new
    NewRelic::Agent.manual_start(
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

  def test_with_custom_attributes
    measure { @dummy.transaction_with_attributes }
  end

  def test_failure
    measure do
      begin
        @dummy.failure
      rescue
        # Whatever...
      end
    end
  end

  TXNAME = "Controller/Blogs/index".freeze

  def test_start_with_tracer_start
    measure do
      if NewRelic::Agent::Tracer.tracing_enabled? &&
          !NewRelic::Agent::Tracer.current_transaction
        finishable = NewRelic::Agent::Tracer.start_transaction(
          name: TXNAME,
          category: :controller
        )
        finishable.finish
      end
    end
  end

  def test_short_transaction_with_datastore_segment
    measure do
      in_transaction do |txn|
        txn.sampled = true
        segment = NewRelic::Agent::Tracer.start_datastore_segment(
          product: "SQLite",
          operation: "insert",
          collection: "Blog"
        )
        segment.finish
      end
    end
  end

  def test_short_transaction_with_external_request_segment
    measure do
      in_transaction do |txn|
        txn.sampled = true
        segment = NewRelic::Agent::Transaction.start_external_request_segment(
          library: "Net::HTTP",
          uri: "http://remotehost.com/blogs/index",
          procedure: "GET"
        )
        segment.finish
      end
    end
  end
end
