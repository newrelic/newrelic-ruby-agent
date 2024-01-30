# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent::Llm
  class ChatCompletionTest < Minitest::Test
    def test_attributes_include_conversation_id
      assert_includes ChatCompletion::ATTRIBUTES, :conversation_id
    end
  end
end
