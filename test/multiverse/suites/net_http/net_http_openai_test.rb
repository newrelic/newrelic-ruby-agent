# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class NetHttpOpenAITest < Minitest::Test
  include NewRelic::Agent::Instrumentation::NetHTTP

  def test_openai_true_when_ruby_openai_prepend_and_ai_monitoring_enabled
    # with_config doesn't work because the value for
    # instrumentation.ruby_openai will be overriden during
    # dependency detection.
    NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :prepend, :'ai_monitoring.enabled' => true}) do
      assert_truthy openai
    end
  end

  def test_openai_true_when_ruby_openai_chain_and_ai_monitoring_enabled
    NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :chain, :'ai_monitoring.enabled' => true}) do
      assert_truthy openai
    end
  end

  def test_openai_false_when_ruby_openai_auto
    NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :auto, :'ai_monitoring.enabled' => true}) do
      refute openai
    end
  end

  def test_openai_false_when_ruby_openai_disabled
    NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :disabled, :'ai_monitoring.enabled' => true}) do
      refute openai
    end
  end

  def test_openai_false_when_ruby_openai_unsatisfied
    NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :unsatisfied, :'ai_monitoring.enabled' => true}) do
      refute openai
    end
  end

  def test_openai_false_when_ai_monitoring_disabled
    NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :prepend, :'ai_monitoring.enabled' => false}) do
      refute openai
    end
  end

  def test_openai_value_memoized # could probs be a better test
    NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :prepend, :'ai_monitoring.enabled' => true}) do
      refute instance_variable_defined?(:@openai)
      assert openai
      assert instance_variable_defined?(:@openai)
    end
  end

  def test_openai_parent_with_all_the_things
    parent_segment = NewRelic::Agent::Transaction::AbstractSegment.new('Llm/embedding/OpenAI/embeddings')
    segment = NewRelic::Agent::Transaction::AbstractSegment.new('Anything')
    segment.parent = parent_segment

    assert_truthy openai_parent?(segment)
  end

  def test_openai_parent_without_segment
    refute openai_parent?(nil)
  end

  def test_opneai_parent_without_parent
    segment = NewRelic::Agent::Transaction::AbstractSegment.new('Anything')

    refute openai_parent?(segment)
  end

  def test_opneai_parent_without_name
    parent_segment = NewRelic::Agent::Transaction::AbstractSegment.new(nil)
    segment = NewRelic::Agent::Transaction::AbstractSegment.new('Anything')
    segment.parent = parent_segment

    refute openai_parent?(segment)
  end

  def test_opneai_parent_without_match
    parent_segment = NewRelic::Agent::Transaction::AbstractSegment.new('doesnt_match')
    segment = NewRelic::Agent::Transaction::AbstractSegment.new('Anything')
    segment.parent = parent_segment

    refute openai_parent?(segment)
  end

  def test_populate_openai_response_headers_without_llm_event
    response = {}
    parent = NewRelic::Agent::Transaction::AbstractSegment.new('Llm/embedding/OpenAI/embeddings')

    refute parent.instance_variable_defined?(:@llm_event)
    assert_nil populate_openai_response_headers(response, parent)
  end

  def test_populate_openai_response_headers_with_llm_event_calls_llm_method
    response = {}
    parent = NewRelic::Agent::Transaction::AbstractSegment.new('Llm/embedding/OpenAI/embeddings')
    mock_llm_event = Minitest::Mock.new
    mock_llm_event.expect :populate_openai_response_headers, nil, [{}]
    parent.llm_event = mock_llm_event

    populate_openai_response_headers(response, parent)
    mock_llm_event.verify
  end
end
