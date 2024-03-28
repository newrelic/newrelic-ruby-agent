# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'

module NewRelic
  module Agent
    class LLMTest < Minitest::Test
      def setup
        NewRelic::Agent::LLM.remove_instance_variable(:@openai) if NewRelic::Agent::LLM.instance_variable_defined?(:@openai)
      end

      # Mocha used in test_populate_openai_response_headers_with_llm_event_calls_llm_method
      def teardown
        mocha_teardown
      end

      def test_openai_true_when_ruby_openai_prepend_and_ai_monitoring_enabled
        # with_config doesn't work because the value for
        # instrumentation.ruby_openai will be overriden during
        # dependency detection.
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :prepend, :'ai_monitoring.enabled' => true}) do
          assert_truthy NewRelic::Agent::LLM.openai?
        end
      end

      def test_openai_true_when_ruby_openai_chain_and_ai_monitoring_enabled
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :chain, :'ai_monitoring.enabled' => true}) do
          assert_truthy NewRelic::Agent::LLM.openai?
        end
      end

      def test_openai_false_when_ruby_openai_auto
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :auto, :'ai_monitoring.enabled' => true}) do
          refute_predicate(NewRelic::Agent::LLM, :openai?)
        end
      end

      def test_openai_false_when_ruby_openai_disabled
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :disabled, :'ai_monitoring.enabled' => true}) do
          refute_predicate(NewRelic::Agent::LLM, :openai?)
        end
      end

      def test_openai_false_when_ruby_openai_unsatisfied
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :unsatisfied, :'ai_monitoring.enabled' => true}) do
          refute_predicate(NewRelic::Agent::LLM, :openai?)
        end
      end

      def test_openai_false_when_ai_monitoring_disabled
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :prepend, :'ai_monitoring.enabled' => false}) do
          refute_predicate(NewRelic::Agent::LLM, :openai?)
        end
      end

      def test_openai_value_memoized # could probs be a better test
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :prepend, :'ai_monitoring.enabled' => true}) do
          refute NewRelic::Agent::LLM.instance_variable_defined?(:@openai)
          assert_predicate(NewRelic::Agent::LLM, :openai?)
          assert NewRelic::Agent::LLM.instance_variable_defined?(:@openai)
        end
      end

      def test_openai_parent_with_all_the_things
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :prepend, :'ai_monitoring.enabled' => true}) do
          parent_segment = NewRelic::Agent::Transaction::AbstractSegment.new('Llm/embedding/OpenAI/embeddings')
          segment = NewRelic::Agent::Transaction::AbstractSegment.new('Anything')
          segment.parent = parent_segment

          assert_truthy NewRelic::Agent::LLM.openai_parent?(segment)
        end
      end

      def test_openai_parent_without_segment
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :auto, :'ai_monitoring.enabled' => true}) do
          refute NewRelic::Agent::LLM.openai_parent?(nil)
        end
      end

      def test_opneai_parent_without_parent
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :auto, :'ai_monitoring.enabled' => true}) do
          segment = NewRelic::Agent::Transaction::AbstractSegment.new('Anything')

          refute NewRelic::Agent::LLM.openai_parent?(segment)
        end
      end

      def test_opneai_parent_without_name
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :auto, :'ai_monitoring.enabled' => true}) do
          parent_segment = NewRelic::Agent::Transaction::AbstractSegment.new(nil)
          segment = NewRelic::Agent::Transaction::AbstractSegment.new('Anything')
          segment.parent = parent_segment

          refute NewRelic::Agent::LLM.openai_parent?(segment)
        end
      end

      def test_opneai_parent_without_match
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :auto, :'ai_monitoring.enabled' => true}) do
          parent_segment = NewRelic::Agent::Transaction::AbstractSegment.new('doesnt_match')
          segment = NewRelic::Agent::Transaction::AbstractSegment.new('Anything')
          segment.parent = parent_segment

          refute NewRelic::Agent::LLM.openai_parent?(segment)
        end
      end

      def test_populate_openai_response_headers_without_llm_event
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :auto, :'ai_monitoring.enabled' => true}) do
          response = {}
          parent = NewRelic::Agent::Transaction::AbstractSegment.new('Llm/embedding/OpenAI/embeddings')

          refute parent.instance_variable_defined?(:@llm_event)
          assert_nil NewRelic::Agent::LLM.populate_openai_response_headers(response, parent)
        end
      end

      def test_populate_openai_response_headers_with_llm_event_calls_llm_method
        NewRelic::Agent.stub(:config, {:'instrumentation.ruby_openai' => :auto, :'ai_monitoring.enabled' => true}) do
          response = {}
          parent = NewRelic::Agent::Transaction::AbstractSegment.new('Llm/embedding/OpenAI/embeddings')
          mock_llm_event = NewRelic::Agent::Llm::Embedding.new
          mock_llm_event.expects(:populate_openai_response_headers).with(response)
          parent.llm_event = mock_llm_event
          NewRelic::Agent::LLM.populate_openai_response_headers(response, parent)
        end
      end
    end
  end
end
