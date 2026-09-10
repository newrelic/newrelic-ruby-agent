# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/instrumentation/active_job'

module NewRelic::Agent::Instrumentation
  class ActiveJobHelperTest < Minitest::Test
    class FakeJob
      def queue_name
        'default'
      end
    end

    def test_rails_formatted_adapters_get_shortened
      name = ActiveJobHelper.clean_adapter_name('ActiveJob::QueueAdapters::InlineAdapter')

      assert_equal 'ActiveJob::Inline', name
    end

    def test_unexpected_name_format
      name = ActiveJobHelper.clean_adapter_name('Not::AnExpected::Adapter')

      assert_equal 'Not::AnExpected::Adapter', name
    end

    def test_span_kind_for_event_is_producer_for_produce
      assert_equal NewRelic::Agent::SpanEventPrimitive::PRODUCER, ActiveJobHelper.span_kind_for_event(:Produce)
    end

    def test_span_kind_for_event_is_consumer_for_consume
      assert_equal NewRelic::Agent::SpanEventPrimitive::CONSUMER, ActiveJobHelper.span_kind_for_event(:Consume)
    end

    def test_run_in_trace_tags_producer_span_kind_for_produce_event
      job = FakeJob.new
      captured_kind = nil
      ActiveJobHelper.stubs(:adapter).returns('ActiveJob::Test')

      in_transaction do
        ActiveJobHelper.run_in_trace(job, proc { captured_kind = NewRelic::Agent::Tracer.current_segment.span_kind }, :Produce)
      end

      assert_equal NewRelic::Agent::SpanEventPrimitive::PRODUCER, captured_kind
    end

    def test_run_in_trace_tags_consumer_span_kind_for_consume_event
      job = FakeJob.new
      captured_kind = nil
      ActiveJobHelper.stubs(:adapter).returns('ActiveJob::Test')

      in_transaction do
        ActiveJobHelper.run_in_trace(job, proc { captured_kind = NewRelic::Agent::Tracer.current_segment.span_kind }, :Consume)
      end

      assert_equal NewRelic::Agent::SpanEventPrimitive::CONSUMER, captured_kind
    end

    def test_run_in_transaction_tags_consumer_span_kind
      job = FakeJob.new
      captured_kind = nil
      ActiveJobHelper.stubs(:adapter).returns('ActiveJob::Test')

      ActiveJobHelper.run_in_transaction(job, proc { captured_kind = NewRelic::Agent::Tracer.current_segment.span_kind })

      assert_equal NewRelic::Agent::SpanEventPrimitive::CONSUMER, captured_kind
    end
  end
end
