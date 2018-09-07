# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

module NewRelic
  module Agent
    class TracerTest < Minitest::Test
      def test_tracer_aliases
        trace_state = Tracer.trace_state
        refute_nil trace_state
      end

      def test_current_transaction_with_transaction
        in_transaction do |txn|
          assert_equal txn, Tracer.current_transaction
        end
      end

      def test_current_transaction_without_transaction
        assert_nil Tracer.current_transaction
      end

      def test_tracing_enabled
        NewRelic::Agent.disable_all_tracing do
          in_transaction do
            NewRelic::Agent.disable_all_tracing do
              refute Tracer.tracing_enabled?
            end
            refute Tracer.tracing_enabled?
          end
        end
        assert Tracer.tracing_enabled?
      end
    end
  end
end
