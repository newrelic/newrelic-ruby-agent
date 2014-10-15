# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/synthetics_monitor'

module NewRelic::Agent
  class SyntheticsMonitorTest < Minitest::Test
    ENCODING_KEY_NOOP         = "\0"
    TRUSTED_ACCOUNT_IDS       = [42,13]

    def setup
      @events  = EventListener.new
      @monitor = SyntheticsMonitor.new(@events)

      NewRelic::Agent.reset_config
      @config = {
        :encoding_key        => ENCODING_KEY_NOOP,
        :trusted_account_ids => TRUSTED_ACCOUNT_IDS
      }
      NewRelic::Agent.config.add_config_for_testing(@config)

      @events.notify(:finished_configuring)
    end

    def test_doesnt_record_synthetics_state_without_header
      in_transaction do
        expects_no_logging(:debug)
        @events.notify(:before_call, {})
      end

      assert_nil NewRelic::Agent::TransactionState.tl_get.synthetics_info
    end

    def test_records_synthetics_state
      synthetics_info = [1, 42, 100, 200, 300]

      in_transaction do
        @events.notify(:before_call, {
          SyntheticsMonitor::SYNTHETICS_HEADER_KEY => json_dump_and_encode(synthetics_info)
        })
      end

      assert_equal synthetics_info, NewRelic::Agent::TransactionState.tl_get.synthetics_info
    end
  end
end
