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

    BAD_ACCOUNT_ID = 7
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
        @events.notify(:before_call, {})
        assert_no_synthetics_payload
      end
    end

    def test_doesnt_record_synthetics_if_incoming_request_higher_version
      synthetics_payload = [BAD_VERSION_ID] + STANDARD_DATA
      with_synthetics_headers(synthetics_payload) do
        assert_no_synthetics_payload
      end
    end

    def test_doesnt_record_synthetics_if_not_trusted_account
      synthetics_payload = [VERSION_ID, BAD_ACCOUNT_ID] + STANDARD_DATA[1..-1]
      with_synthetics_headers(synthetics_payload) do
        assert_no_synthetics_payload
      end
    end

    def test_doesnt_record_synthetics_if_data_too_short
      synthetics_payload = [VERSION_ID, ACCOUNT_ID]
      with_synthetics_headers(synthetics_payload) do
        assert_no_synthetics_payload
      end
    end

    def test_records_synthetics_state_from_header
      key = SyntheticsMonitor::SYNTHETICS_HEADER_KEY
      synthetics_payload = [VERSION_ID] + STANDARD_DATA
      with_synthetics_headers(synthetics_payload, key) do
        state = NewRelic::Agent::TransactionState.tl_get
        txn = state.current_transaction
        assert_equal @last_encoded_header, txn.raw_synthetics_header
        assert_equal synthetics_payload,   txn.synthetics_payload
      end
    end

    def synthetics_header(payload, header_key = SyntheticsMonitor::SYNTHETICS_HEADER_KEY)
      @last_encoded_header = json_dump_and_encode(payload)
      { header_key => @last_encoded_header }
    end

    def assert_no_synthetics_payload
      assert_nil NewRelic::Agent::TransactionState.tl_get.current_transaction.synthetics_payload
    end

    def with_synthetics_headers(payload, header_key = SyntheticsMonitor::SYNTHETICS_HEADER_KEY)
      in_transaction do
        @events.notify(:before_call, synthetics_header(payload, header_key))
        yield
      end
    end
  end
end
