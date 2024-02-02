# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class RubyOpenAIInstrumentationTest < Minitest::Test
  include OpenAIHelpers

  def setup
    @aggregator = NewRelic::Agent.agent.custom_event_aggregator
    NewRelic::Agent.drop_buffered_data
  end

  def test_instrumentation_doesnt_record_anything_with_other_paths_that_use_json_post
    in_transaction do
      client.stub(:conn, faraday_connection) do
        client.json_post(path: '/edits', parameters: edits_params)
      end
    end

    refute_metrics_recorded(["Ruby/ML/OpenAI/#{::OpenAI::VERSION}"])
  end

  def test_openai_metric_recorded_for_chat_completions_every_time
    in_transaction do
      client.stub(:conn, faraday_connection) do
        client.chat(parameters: chat_params)
        client.chat(parameters: chat_params)
      end
    end

    assert_metrics_recorded({"Ruby/ML/OpenAI/#{::OpenAI::VERSION}" => {call_count: 2}})
  end

  def test_openai_chat_completion_segment_name
    txn = in_transaction do
      client.stub(:conn, faraday_connection) do
        client.chat(parameters: chat_params)
      end
    end

    refute_nil chat_completion_segment(txn)
  end

  def test_summary_event_has_duration_of_segment
    txn = in_transaction do
      client.stub(:conn, faraday_connection) do
        client.chat(parameters: chat_params)
      end
    end

    segment = chat_completion_segment(txn)

    assert_equal segment.duration, segment.chat_completion_summary.duration
  end

  def test_chat_completion_records_summary_event
    in_transaction do
      client.stub(:conn, faraday_connection) do
        client.chat(parameters: chat_params)
      end
    end
    _, events = @aggregator.harvest!
    summary_events = events.filter { |event| event[0]['type'] == NewRelic::Agent::Llm::ChatCompletionSummary::EVENT_NAME }

    assert_equal 1, summary_events.length

    # summary_event = summary_events[0]
    # assert it has all the required attributes?
  end

  def test_chat_completion_records_message_events
    in_transaction do
      client.stub(:conn, faraday_connection) do
        client.chat(parameters: chat_params)
      end
    end
    _, events = @aggregator.harvest!
    summary_events = events.filter { |event| event[0]['type'] == NewRelic::Agent::Llm::ChatCompletionMessage::EVENT_NAME }

    assert_equal 5, summary_events.length
    # assert the events have the right attributes?
  end

  def test_segment_error_captured_if_raised
    txn = raise_segment_error

    assert_segment_noticed_error(txn, /.*OpenAI\/create/, RuntimeError.name, /deception/i)
  end

  def test_segment_summary_event_sets_error_true_if_raised
    txn = raise_segment_error

    segment = chat_completion_segment(txn)

    refute_nil segment.chat_completion_summary
    assert segment.chat_completion_summary.error
  end

  def test_chat_completion_returns_chat_completion_body
    result = nil

    in_transaction do
      client.stub(:conn, faraday_connection) do
        result = client.chat(parameters: chat_params)
      end
    end

    assert_equal ChatResponse.new.body, result
  end

  def test_set_llm_agent_attribute_on_transaction
    in_transaction do |txn|
      client.stub(:conn, faraday_connection) do
        result = client.chat(parameters: chat_params)
      end
    end

    assert_truthy harvest_transaction_events![1][0][2][:llm]
  end

  def test_set_llm_agent_attribute_on_error_transaction
    in_transaction do |txn|
      client.stub(:conn, faraday_connection) do
        client.chat(parameters: chat_params)
        NewRelic::Agent.notice_error(StandardError.new)
      end
    end

    assert_truthy harvest_error_events![1][0][2][:llm]
  end
end
