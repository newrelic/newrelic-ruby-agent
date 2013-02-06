require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

module NewRelic::Agent
  class CrossProcessMonitorTest < Test::Unit::TestCase
    AGENT_CROSS_PROCESS_ID    = "qwerty"
    REQUEST_CROSS_PROCESS_ID  = "42#1234"

    TRANSACTION_NAME          = 'transaction'
    QUEUE_TIME                = 1000
    APP_TIME                  = 2000

    ENCODING_KEY_NOOP         = "\0"
    TRUSTED_ACCOUNT_IDS       = [42,13]

    CROSS_PROCESS_ID_POSITION = 0
    TRANSACTION_NAME_POSITION = 1
    QUEUE_TIME_POSITION       = 2
    APP_TIME_POSITION         = 3
    CONTENT_LENGTH_POSITION   = 4

    def setup
      @response = {}

      @monitor = NewRelic::Agent::CrossProcessMonitor.new()
      @monitor.finish_setup(
        :cross_process_id => AGENT_CROSS_PROCESS_ID,
        :encoding_key => ENCODING_KEY_NOOP,
        :trusted_account_ids => TRUSTED_ACCOUNT_IDS)
      @monitor.register_event_listeners
    end

    def teardown
      NewRelic::Agent.instance.events.clear
    end

    #
    # Helpers
    #

    def when_request_runs(request=for_id(REQUEST_CROSS_PROCESS_ID))
      @monitor.save_client_cross_process_id(request)
      @monitor.set_transaction_custom_parameters
      @monitor.insert_response_header(request, @response)
    end

    def when_request_has_error(request=for_id(REQUEST_CROSS_PROCESS_ID))
      options = {}
      @monitor.save_client_cross_process_id(request)
      @monitor.set_error_custom_parameters(options)
      @monitor.insert_response_header(request, @response)

      options
    end

    def with_default_timings
      NewRelic::Agent::BrowserMonitoring.stubs(:timings).returns(stub(
          :transaction_name => TRANSACTION_NAME,
          :queue_time_in_seconds => QUEUE_TIME,
          :app_time_in_seconds => APP_TIME))
    end

    def for_id(id)
      encoded_id = id == "" ? "" : Base64.encode64(id)
      { 'X-NewRelic-ID' => encoded_id }
    end

    def response_app_data
      @response['X-NewRelic-App-Data']
    end

    def unpacked_response
      NewRelic.json_load(Base64.decode64(response_app_data))
    end


    #
    # Tests
    #

    def test_adds_response_header
      with_default_timings

      when_request_runs

      assert_equal [AGENT_CROSS_PROCESS_ID, TRANSACTION_NAME, QUEUE_TIME, APP_TIME, -1], unpacked_response
    end

    def test_strips_bad_characters_in_transaction_name
      NewRelic::Agent::BrowserMonitoring.stubs(:timings).returns(stub(
          :transaction_name => "\"'goo",
          :queue_time_in_seconds => QUEUE_TIME,
          :app_time_in_seconds => APP_TIME))

      when_request_runs

      assert_equal "goo", unpacked_response[TRANSACTION_NAME_POSITION]
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
      @monitor.finish_setup(
        :cross_process_id => nil,
        :encoding_key => ENCODING_KEY_NOOP,
        :trusted_account_ids => TRUSTED_ACCOUNT_IDS)

      when_request_runs
      assert_nil response_app_data
    end

    def test_doesnt_add_header_if_config_disabled
      with_config(:'cross_process.enabled' => false) do
        when_request_runs
        assert_nil response_app_data
      end
    end

    def test_includes_content_length
      with_default_timings

      when_request_runs(for_id(REQUEST_CROSS_PROCESS_ID).merge("Content-Length" => 3000))
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

      NewRelic::Agent.expects(:add_custom_parameters).once

      when_request_runs
    end

    def test_error_writes_custom_parameters
      with_default_timings

      options = when_request_has_error

      assert_equal REQUEST_CROSS_PROCESS_ID, options[:client_cross_process_id]
    end

    def test_error_doesnt_write_custom_parameters_if_no_id
      with_default_timings

      options = when_request_has_error(for_id(''))

      assert_equal false, options.key?(:client_cross_process_id)
    end

    def test_writes_metric
      with_default_timings

      metric = mock()
      metric.expects(:record_data_point).with(APP_TIME)
      NewRelic::Agent.instance.stats_engine.stubs(:get_stats_no_scope).returns(metric)

      when_request_runs
    end

    def test_doesnt_write_metric_if_id_blank
      with_default_timings
      NewRelic::Agent.instance.stats_engine.expects(:get_stats_no_scope).never

      when_request_runs(for_id(''))
    end

    def test_decoding_blank
      assert_equal "",
        NewRelic::Agent::CrossProcessMonitor::EncodingFunctions.decode_with_key( 'querty', "" )
    end

    def test_encode_with_nil_uses_empty_key
      assert_equal "querty",
        NewRelic::Agent::CrossProcessMonitor::EncodingFunctions.encode_with_key( nil, 'querty' )
    end

  end
end
