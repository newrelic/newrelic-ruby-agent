# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class DistributedTracePayloadTest < Minitest::Test
      def test_payload_is_created_if_connected
        with_config application_id: "46954", cross_process_id: "190#222" do
          freeze_time
          created_at = Time.now.to_f
          payload = DistributedTracePayload.new
          unfreeze_time

          assert_equal "46954", payload.caller_app_id
          assert_equal "190", payload.caller_account_id
          assert_equal created_at, payload.timestamp
        end
      end
    end
  end
end
