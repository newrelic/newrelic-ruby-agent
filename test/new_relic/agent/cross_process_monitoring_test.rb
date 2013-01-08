require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

module NewRelic::Agent
  class CrossProcessMonitorTest < Test::Unit::TestCase
    AGENT_CROSS_PROCESS_ID = "qwerty"
    REQUEST_CROSS_PROCESS_ID = "42#1234"

    ENCODING_KEY_NOOP = "\0"
    TRUSTED_ACCOUNT_IDS = [42,13]

    CROSS_PROCESS_ID_POSITION = 0
    TRANSACTION_NAME_POSITION = 1
    QUEUE_TIME_POSITION = 2
    APP_TIME_POSITION = 3
    CONTENT_LENGTH_POSITION = 4

    def setup
      @response = {}

      @monitor = NewRelic::Agent::CrossProcessMonitor.new()
      @monitor.finish_setup(
        :cross_process_id => AGENT_CROSS_PROCESS_ID,
        :encoding_key => ENCODING_KEY_NOOP,
        :trusted_account_ids => TRUSTED_ACCOUNT_IDS)
    end

    def test_adds_response_header
      with_default_timings

      @monitor.insert_response_header(request(REQUEST_CROSS_PROCESS_ID), @response)

      assert_equal ["qwerty", "transaction", 1000, 2000, -1], unpacked_response
    end

    def test_strips_bad_characters_in_transaction_name
      NewRelic::Agent::BrowserMonitoring.stubs(:timings).returns(stub(
          :transaction_name => "\"'goo",
          :queue_time_in_seconds => 1000,
          :app_time_in_seconds => 2000))

      @monitor.insert_response_header(request(REQUEST_CROSS_PROCESS_ID), @response)

      assert_equal "goo", unpacked_response[TRANSACTION_NAME_POSITION]
    end

    def test_doesnt_write_response_header_if_id_blank
      with_default_timings

      @monitor.insert_response_header(request(''), @response)
      assert_nil response_app_data
    end

    def test_doesnt_write_response_header_if_untrusted_id
      with_default_timings

      @monitor.insert_response_header(request("4#1234"), @response)
      assert_nil response_app_data
    end

    def test_doesnt_write_response_header_if_improperly_formatted_id
      with_default_timings

      @monitor.insert_response_header(request("42"), @response)
      assert_nil response_app_data
    end

    def test_doesnt_add_header_if_no_id_in_request
      @monitor.insert_response_header({}, @response)
      assert_nil response_app_data
    end

    def test_doesnt_add_header_if_no_id_on_agent
      @monitor.finish_setup(
        :cross_process_id => nil,
        :encoding_key => ENCODING_KEY_NOOP,
        :trusted_account_ids => TRUSTED_ACCOUNT_IDS)

      @monitor.insert_response_header(request(REQUEST_CROSS_PROCESS_ID), @response)
      assert_nil response_app_data
    end

    def test_doesnt_add_header_if_config_disabled
      with_config(:'cross_process.enabled' => false) do
        @monitor.insert_response_header(request(REQUEST_CROSS_PROCESS_ID), @response)
        assert_nil response_app_data
      end
    end

    def test_includes_content_length
      with_default_timings

      @monitor.insert_response_header(request(REQUEST_CROSS_PROCESS_ID).merge("Content-Length" => 3000), @response)
      assert_equal 3000, unpacked_response[CONTENT_LENGTH_POSITION]
    end

    def test_finds_content_length_from_headers
      %w{Content-Length HTTP_CONTENT_LENGTH CONTENT_LENGTH cOnTeNt-LeNgTh}.each do |key|
        request = { key => 42 }

        assert_equal(42, @monitor.content_length_from_request(request), \
          "Failed to find header on key #{key}")
      end
    end

    def test_finds_id_from_headers
      %w{X-NewRelic-ID HTTP_X_NEWRELIC_ID X_NEWRELIC_ID}.each do |key|
        request = { key => REQUEST_CROSS_PROCESS_ID }

        assert_equal(
          REQUEST_CROSS_PROCESS_ID, \
          @monitor.id_from_request(request),
          "Failed to find header on key #{key}")
      end
    end

    def test_writes_metric
      with_default_timings

      metric = mock()
      metric.expects(:record_data_point).with(2000)
      NewRelic::Agent.instance.stats_engine.stubs(:get_stats_no_scope).returns(metric)

      @monitor.insert_response_header(request(REQUEST_CROSS_PROCESS_ID), @response)
    end

    def test_doesnt_write_metric_if_id_blank
      with_default_timings
      NewRelic::Agent.instance.stats_engine.expects(:get_stats_no_scope).never

      @monitor.insert_response_header(request(''), @response)
    end

    def test_doesnt_find_id_in_headers
      request = {}
      assert_nil @monitor.id_from_request(request)
    end

    def test_decoding_blank
      assert_equal "", @monitor.decode_with_key("")
    end

    def test_get_bytes_with_nil
      assert_equal [], @monitor.send(:get_bytes, nil)
    end

    def with_default_timings
      NewRelic::Agent::BrowserMonitoring.stubs(:timings).returns(stub(
          :transaction_name => "transaction",
          :queue_time_in_seconds => 1000,
          :app_time_in_seconds => 2000))
    end

    def request(id)
      encoded_id = id == "" ? "" : Base64.encode64(id)
      { 'X-NewRelic-ID' => encoded_id }
    end

    def response_app_data
      @response['X-NewRelic-App-Data']
    end

    def unpacked_response
      # Assumes array is valid JSON and Ruby, which is currently is
      eval(Base64.decode64(response_app_data))
    end
  end
end
