# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class RubyOpenAIInstrumentationTest < Minitest::Test
  include OpenAIHelpers

  def test_instrumentation_doesnt_interfere_with_other_methods_that_use_json_post
  end

  def test_openai_metric_recorded_for_embeddings_every_time
  end

  def test_openai_metric_recorded_for_chat_completions_every_time
  end

  def test_openai_embedding_segment_name
  end

  def test_openai_chat_completion_segment_name
  end

  def test_embeddings_records_embedding_event
  end

  def test_chat_completion_records_summary_event
    in_transaction do
      client.stub(:conn, faraday_connection) do
        client.chat(parameters: chat_params)
      end
    end
    _, events = NewRelic::Agent.agent.custom_event_aggregator.harvest!

    assert_equal 6, events.size
  end

  def test_net_http_segment_adds_response_header_attributes_to_event
    # TODO: the stubs used in the test_chat_completion_records_summary_event
    # do not trigger the Net::HTTP instrumentation
    # we need to stub differently to make that get called
    # or maybe does this stuff go into the Net::HTTP tests?
  end
end
