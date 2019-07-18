# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/trace_context_payload'

module NewRelic
  module Agent
    class TraceContextPayloadTest < Minitest::Test
      def test_to_s
        payload = TraceContextPayload.new

        payload.parent_account_id = "12345"
        payload.parent_app_id = "6789"

        payload.id = "f85f42fd82a4cf1d"

        payload.transaction_id = "164d3b4b0d09cb05"
        payload.sampled = true
        payload.priority = 0.123

        assert_equal "0-0-12345-6789-f85f42fd82a4cf1d-164d3b4b0d09cb05-1-0.123-#{payload.timestamp}", payload.to_s
      end
    end
  end
end
