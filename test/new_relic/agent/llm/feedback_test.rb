# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent::Llm
  class FeedbackTest < Minitest::Test
    def setup
      NewRelic::Agent.drop_buffered_data
      @trace_id = '01234567890'
    end

    def test_record_llm_feedback_event_records_required_attributes
      in_transaction do
        NewRelic::Agent.record_llm_feedback_event(trace_id: @trace_id, rating: 5)
        _, events = NewRelic::Agent.agent.custom_event_aggregator.harvest!
        type, attributes = events[0]

        assert_equal 'LlmFeedbackMessage', type['type']
        assert_equal @trace_id, attributes['trace_id']
        assert_equal 5, attributes['rating']
        assert_equal 'Ruby', attributes['ingest_source']
        assert attributes['id']
      end
    end

    def test_record_llm_feedback_event_records_optional_attributes
      in_transaction do
        NewRelic::Agent.record_llm_feedback_event(trace_id: @trace_id, rating: 5,
          category: 'Helpful', message: 'Looks good!', metadata: {'pop' => 'tart', 'toaster' => 'strudel'})
        _, events = NewRelic::Agent.agent.custom_event_aggregator.harvest!
        _, attributes = events[0]

        assert_equal 'Helpful', attributes['category']
        assert_equal 'Looks good!', attributes['message']
        assert_equal 'tart', attributes['pop']
        assert_equal 'strudel', attributes['toaster']
      end
    end

    def test_record_llm_feedback_event_raises_missing_required_parameter
      assert_raises(ArgumentError) { NewRelic::Agent.record_llm_feedback_event(trace_id: @trace_id) }
    end

    def test_record_llm_feedback_event_invalid_param
      assert_raises(ArgumentError) {
        NewRelic::Agent.record_llm_feedback_event(
          trace_id: @trace_id,
          rating: 5,
          food: 'blueberry'
        )
      }
    end

    def test_record_llm_feedback_event_rescues_exception
      NewRelic::Agent.stub(:logger, NewRelic::Agent::MemoryLogger.new) do
        NewRelic::Agent.stub(:record_custom_event, proc { |*_args| raise 'kaboom' }) do
          NewRelic::Agent.record_llm_feedback_event(trace_id: @trace_id, rating: 5)
        end

        assert_logged(/record_llm_feedback_event/)
      end
    end

    def test_feedback_api_supportability_metric_recorded
      in_transaction do
        NewRelic::Agent.record_llm_feedback_event(trace_id: @trace_id, rating: 5)
        NewRelic::Agent.agent.custom_event_aggregator.harvest!
      end

      assert_metrics_recorded('Supportability/API/record_llm_feedback_event')
    end

    def test_record_llm_feedback_event_requires_distributed_tracing
      with_config(:'distributed_tracing.enabled' => false) do
        in_transaction do
          NewRelic::Agent.record_llm_feedback_event(trace_id: @trace_id, rating: 5)
          _, events = NewRelic::Agent.agent.custom_event_aggregator.harvest!
          _, attributes = events[0]

          assert_nil attributes
        end
      end
    end

    def assert_logged(expected)
      found = NewRelic::Agent.logger.messages.any? { |m| m[1][0].match?(expected) }

      assert(found, "Didn't see log message: '#{expected}'")
    end
  end
end
