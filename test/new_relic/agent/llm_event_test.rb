# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'


module NewRelic::Agent
  class LlmEventTest < Minitest::Test
    # def test_attributes
    #   NewRelic::Agent::LlmEvent.new

    # end

    def test_attributes_chat
      NewRelic::Agent::LlmEvent::ChatCompletion.new
    end
  end
end