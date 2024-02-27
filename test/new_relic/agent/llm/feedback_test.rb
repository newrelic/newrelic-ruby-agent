# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent::Llm
  class FeedbackTest < Minitest::Test
    def setup
      NewRelic::Agent.drop_buffered_data
    end

    def test_record_llm_feedback_event_required_attributes
      in_transaction do |txn|
        NewRelic::Agent::Tracer.record_llm_feedback_event(trace_id: '01234567890', rating: 5)

        _, events = NewRelic::Agent.agent.custom_event_aggregator.harvest!
        type, attributes = events[0]

        assert_equal 'LlmFeedbackMessage', type['type']
        assert_equal '01234567890', attributes['trace_id']
        assert_equal 5, attributes['rating']
        assert_equal 'Ruby', attributes['ingest_source']
        assert attributes['id']
      end
    end

    # def test_record_llm_feedback_event_raises_not_in_transaction
    # end

    def test_record_llm_feedback_event_records_optional_attributes
      in_transaction do |txn|
        NewRelic::Agent::Tracer.record_llm_feedback_event(trace_id: '01234567890', rating: 5,
          message: 'Looks good!', metadata: {"pop"=> 'tart'})

        _, events = NewRelic::Agent.agent.custom_event_aggregator.harvest!
        type, attributes = events[0]

        assert_equal 'Looks good!', attributes['message']
        assert_equal 'tart', attributes['metadata.pop']
      end
    end

    def test_record_llm_feedback_event_raises_missing_required_parameter
      assert_raises(ArgumentError) { NewRelic::Agent::Tracer.record_llm_feedback_event(trace_id: '01234567890')}
    end
  end
end
