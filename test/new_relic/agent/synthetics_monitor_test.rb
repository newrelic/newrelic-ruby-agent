# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/synthetics_monitor'

module NewRelic::Agent
  class SyntheticsMonitorTest < Minitest::Test
    ENCODING_KEY_NOOP         = "\0"
    TRUSTED_ACCOUNT_IDS       = [42,13]

    VERSION_ID  = 1
    ACCOUNT_ID  = 42
    RESOURCE_ID = 100
    JOB_ID      = 200
    MONITOR_ID  = 300

    BAD_VERSION_ID = 2

    STANDARD_DATA = [ACCOUNT_ID, RESOURCE_ID, JOB_ID, MONITOR_ID]

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
        # Make sure we're not just erroring in the event notification handler
        expects_no_logging(:debug)

        @events.notify(:before_call, {})
        assert_nil NewRelic::Agent::TransactionState.tl_get.synthetics_info
      end
    end

    def test_doesnt_record_synthetics_if_incoming_request_higher_version
      synthetics_info = [BAD_VERSION_ID] + STANDARD_DATA

      in_transaction do
        @events.notify(:before_call, synthetics_header(synthetics_info))
        assert_nil NewRelic::Agent::TransactionState.tl_get.synthetics_info
      end
    end

    def test_records_synthetics_state
      synthetics_info = [VERSION_ID] + STANDARD_DATA

      in_transaction do
        @events.notify(:before_call, synthetics_header(synthetics_info))
        assert_equal synthetics_info, NewRelic::Agent::TransactionState.tl_get.synthetics_info
      end
    end

    def synthetics_header(payload)
      { SyntheticsMonitor::SYNTHETICS_HEADER_KEY => json_dump_and_encode(payload) }
    end
  end
end
