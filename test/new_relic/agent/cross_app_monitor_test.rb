# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

module NewRelic::Agent
  class CrossAppMonitorTest < Test::Unit::TestCase
    NEWRELIC_ID_HEADER        = NewRelic::Agent::CrossAppMonitor::NEWRELIC_ID_HEADER
    NEWRELIC_TXN_HEADER       = NewRelic::Agent::CrossAppMonitor::NEWRELIC_TXN_HEADER

    AGENT_CROSS_APP_ID        = "qwerty"
    REQUEST_CROSS_APP_ID      = "42#1234"
    TRANSACTION_GUID          = '941B0E8001E444E8'
    REF_TRANSACTION_GUID      = '830092CDE59421D4'

    TRANSACTION_NAME          = 'transaction'
    QUEUE_TIME                = 1000
    APP_TIME                  = 2000

    ENCODING_KEY_NOOP         = "\0"
    TRUSTED_ACCOUNT_IDS       = [42,13]

    CROSS_APP_ID_POSITION     = 0
    TRANSACTION_NAME_POSITION = 1
    QUEUE_TIME_POSITION       = 2
    APP_TIME_POSITION         = 3
    CONTENT_LENGTH_POSITION   = 4

    def setup
      NewRelic::Agent.reset_config
      NewRelic::Agent.instance.events.clear
      @response = {}

      @monitor = NewRelic::Agent::CrossAppMonitor.new()
      @config = {
        :cross_process_id => AGENT_CROSS_APP_ID,
        :encoding_key => ENCODING_KEY_NOOP,
        :trusted_account_ids => TRUSTED_ACCOUNT_IDS
      }

      NewRelic::Agent.config.apply_config( @config )
      @monitor.register_event_listeners
      NewRelic::Agent::TransactionState.get.request_guid = TRANSACTION_GUID
    end

    def teardown
      NewRelic::Agent.config.remove_config( @config )
      NewRelic::Agent.instance.events.clear
    end


    #
    # Tests
    #

    def test_adds_response_header
      with_default_timings

      when_request_runs

      assert_equal 'WyJxd2VydHkiLCJ0cmFuc2FjdGlvbiIsMTAwMC4wLDIwMDAuMCwtMSwiOTQxQjBFODAwMUU0NDRFOCJd', response_app_data
      assert_equal [AGENT_CROSS_APP_ID, TRANSACTION_NAME, QUEUE_TIME, APP_TIME, -1, TRANSACTION_GUID], unpacked_response
    end

    def test_encodes_transaction_name
      NewRelic::Agent::TransactionState.any_instance.stubs(:timings).returns(stub(
          :transaction_name => "\"'goo",
          :queue_time_in_seconds => QUEUE_TIME,
          :app_time_in_seconds => APP_TIME))

      when_request_runs

      assert_equal "\"'goo", unpacked_response[TRANSACTION_NAME_POSITION]
    end

    def test_doesnt_write_response_header_if_id_blank
      with_default_timings

      when_request_runs(for_id(''))
      assert_nil response_app_data
    end

    def test_doesnt_write_response_header_if_untrusted_id
      with_default_timings

      when_request_runs(for_id("4#1234"))
      assert_nil response_app_data
    end

    def test_doesnt_write_response_header_if_improperly_formatted_id
      with_default_timings

      when_request_runs(for_id("42"))
      assert_nil response_app_data
    end

    def test_doesnt_add_header_if_no_id_in_request
      when_request_runs({})
      assert_nil response_app_data
    end

    def test_doesnt_add_header_if_no_id_on_agent
      # Since a +nil+ will make it fall back to the config installed in setup,
      # we need to remove that first in order to test the no-id case
      newconfig = @config.merge( :cross_process_id => nil )
      NewRelic::Agent.config.remove_config( @config )

      with_config( newconfig ) do
        when_request_runs
        assert_nil response_app_data
      end
    end

    def test_doesnt_add_header_if_config_disabled
      with_config(:"cross_application_tracer.enabled" => false) do
        when_request_runs
        assert_nil response_app_data
      end
    end

    def test_includes_content_length
      with_default_timings

      when_request_runs(for_id(REQUEST_CROSS_APP_ID).merge("Content-Length" => 3000))
      assert_equal 3000, unpacked_response[CONTENT_LENGTH_POSITION]
    end

    def test_finds_content_length_from_headers
      %w{Content-Length HTTP_CONTENT_LENGTH CONTENT_LENGTH cOnTeNt-LeNgTh}.each do |key|
        request = { key => 42 }

        assert_equal(42, @monitor.content_length_from_request(request), \
          "Failed to find header on key #{key}")
      end
    end

    def test_writes_custom_parameters
      with_default_timings

      NewRelic::Agent.expects(:add_custom_parameters).with(:client_cross_process_id => REQUEST_CROSS_APP_ID)
      NewRelic::Agent.expects(:add_custom_parameters).with(:referring_transaction_guid => REF_TRANSACTION_GUID)

      when_request_runs
    end

    def test_error_writes_custom_parameters
      with_default_timings

      options = when_request_has_error

      assert_equal REQUEST_CROSS_APP_ID, options[:client_cross_process_id]
    end

    def test_error_doesnt_write_custom_parameters_if_no_id
      with_default_timings

      options = when_request_has_error(for_id(''))

      assert_equal false, options.key?(:client_cross_process_id)
    end

    def test_writes_metric
      with_default_timings

      expected_metric_name = "ClientApplication/#{REQUEST_CROSS_APP_ID}/all"
      NewRelic::Agent.instance.stats_engine.expects(:record_metrics). \
        with(expected_metric_name, APP_TIME)

      when_request_runs
    end

    def test_doesnt_write_metric_if_id_blank
      with_default_timings

      NewRelic::Agent.instance.stats_engine.expects(:record_metrics).never

      when_request_runs(for_id(''))
    end

    def test_decoding_blank
      assert_equal "",
        NewRelic::Agent::CrossAppMonitor::EncodingFunctions.decode_with_key( 'querty', "" )
    end

    def test_encode_with_nil_uses_empty_key
      assert_equal "querty",
        NewRelic::Agent::CrossAppMonitor::EncodingFunctions.encode_with_key( nil, 'querty' )
    end

    def test_encoding_functions_can_roundtrip_utf8_text
      str = 'Анастасі́я Олексі́ївна Каме́нських'
      encoded = NewRelic::Agent::CrossAppMonitor::EncodingFunctions.obfuscate_with_key( 'potap', str )
      decoded = NewRelic::Agent::CrossAppMonitor::EncodingFunctions.decode_with_key( 'potap', encoded )
      decoded.force_encoding( 'utf-8' ) if decoded.respond_to?( :force_encoding )
      assert_equal str, decoded
    end

    def test_setting_response_headers_freezes_transaction_name
      in_transaction do
        assert !NewRelic::Agent::Transaction.current.name_frozen?
        when_request_runs
        assert NewRelic::Agent::Transaction.current.name_frozen?
      end
    end

    #
    # Helpers
    #

    def when_request_runs(request=for_id(REQUEST_CROSS_APP_ID))
      event_listener = NewRelic::Agent.instance.events
      event_listener.notify(:before_call, request)
      event_listener.notify(:start_transaction, 'a name')
      event_listener.notify(:after_call, request, [200, @response, ''])
    end

    def when_request_has_error(request=for_id(REQUEST_CROSS_APP_ID))
      options = {}
      event_listener = NewRelic::Agent.instance.events
      event_listener.notify(:before_call, request)
      event_listener.notify(:notice_error, nil, options)
      event_listener.notify(:after_call, request, [500, @response, ''])

      options
    end

    def with_default_timings
      NewRelic::Agent::TransactionState.any_instance.stubs(:timings).returns(stub(
          :transaction_name => TRANSACTION_NAME,
          :queue_time_in_seconds => QUEUE_TIME,
          :app_time_in_seconds => APP_TIME))
    end

    def for_id(id)
      encoded_id = id == "" ? "" : Base64.encode64(id)
      encoded_txn_info = Base64.encode64( NewRelic.json_dump([ REF_TRANSACTION_GUID, false ]) )

      return {
        NEWRELIC_ID_HEADER => encoded_id,
        NEWRELIC_TXN_HEADER => encoded_txn_info,
      }
    end

    def response_app_data
      @response['X-NewRelic-App-Data']
    end

    def unpacked_response
      return nil unless response_app_data
      NewRelic.json_load(Base64.decode64(response_app_data))
    end

  end
end
