# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class HybridAgentTest < Minitest::Test
  def test_does_not_create_segment_without_a_transaction
    # do work in span
    # opentelemetry span should not be created
    # #= current otel span
    # there should be no transaction
    # != current_transaction
  end

  def
  # Add tests here
end
