# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../agent_helper'

module NewRelic::Agent
  class LlmEventTest < Minitest::Test
    # def test_attributes
    #   NewRelic::Agent::LlmEvent.new
    def setup
      events = NewRelic::Agent.instance.events
      @aggregator = NewRelic::Agent::CustomEventAggregator.new(events)
    end

    def test_attributes_chat
      NewRelic::Agent::LlmEvent::ChatCompletion::Message.new(id: 123)
    end

    def test_attribute_merge
      message = NewRelic::Agent::LlmEvent::ChatCompletion::Message.new(content: 'hi', role: 'speaker', api_key_last_four_digits: 'sk-0', conversation_id: 123, id: 345, app_name: NewRelic::Agent.config[:app_name])
      message.record
      binding.irb
      _, events = @aggregator.harvest!
      # NewRelic::Agent.agent.send(:harvest_and_send_custom_event_data)
      # returned = first_call_for('custom_event_data').events
      # events.first[0].delete('priority')
      # event = events.first

      expected_event = [{'type' => 'DummyType', 'timestamp' => 'bhjbjh'},
        {'foo' => 'bar', 'baz' => 'qux'}]

      assert_equal(expected_event, events)
    end
  end
end
