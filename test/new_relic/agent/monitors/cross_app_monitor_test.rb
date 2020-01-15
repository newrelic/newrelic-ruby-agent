# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

module NewRelic::Agent
  class CrossAppMonitorTest < Minitest::Test
    NEWRELIC_ID_HEADER        = DistributedTracing::CrossAppMonitor::NEWRELIC_ID_HEADER_KEY
    NEWRELIC_TXN_HEADER       = DistributedTracing::CrossAppMonitor::NEWRELIC_TXN_HEADER_KEY
    CONTENT_LENGTH_KEY        = "HTTP_CONTENT_LENGTH"

    AGENT_CROSS_APP_ID        = "qwerty"
    REQUEST_CROSS_APP_ID      = "42#1234"
    TRANSACTION_GUID          = '941B0E8001E444E8'
    REF_TRANSACTION_GUID      = '830092CDE59421D4'

    TRANSACTION_NAME          = 'transaction'
    QUEUE_TIME                = 1.0
    APP_TIME                  = 2.0

    ENCODING_KEY_NOOP         = "\0"
    TRUSTED_ACCOUNT_IDS       = [42,13]

    CROSS_APP_ID_POSITION     = 0
    TRANSACTION_NAME_POSITION = 1
    QUEUE_TIME_POSITION       = 2
    APP_TIME_POSITION         = 3
    CONTENT_LENGTH_POSITION   = 4

    def setup
      NewRelic::Agent.reset_config
      NewRelic::Agent.drop_buffered_data
      @events = EventListener.new
      @response = {}

      @monitor = DistributedTracing::CrossAppMonitor.new(@events)
      @config = {
        :cross_process_id       => AGENT_CROSS_APP_ID,
        :encoding_key           => ENCODING_KEY_NOOP,
        :trusted_account_ids    => TRUSTED_ACCOUNT_IDS,
        :disable_harvest_thread => true,
        :'cross_application_tracer.enabled' => true,
        :'distributed_tracing.enabled' => false,
      }

      NewRelic::Agent.config.add_config_for_testing(@config)
      @events.notify(:initial_configuration_complete)
    end

    def teardown
      NewRelic::Agent.config.remove_config(@config)
      @events.clear
    end


    #
    # Tests
    #

    def test_adds_response_header
      Transaction.any_instance.stubs(:queue_time).returns(QUEUE_TIME)

      when_request_runs for_id(REQUEST_CROSS_APP_ID), 'transaction', APP_TIME

      assert_equal [AGENT_CROSS_APP_ID, TRANSACTION_NAME, QUEUE_TIME, APP_TIME, -1, TRANSACTION_GUID], unpacked_response
    end

    def test_encodes_transaction_name
      when_request_runs for_id(REQUEST_CROSS_APP_ID), %("'goo), APP_TIME
      assert_equal "\"'goo", unpacked_response[TRANSACTION_NAME_POSITION]
    end

    def test_doesnt_write_response_header_if_id_blank
      when_request_runs(for_id(''))
      assert_nil response_app_data
    end

    def test_doesnt_write_response_header_if_untrusted_id
      when_request_runs(for_id("4#1234"))
      assert_nil response_app_data
    end

    def test_doesnt_write_response_header_if_improperly_formatted_id
      when_request_runs(for_id("42"))
      assert_nil response_app_data
    end

    def test_doesnt_add_header_if_no_id_in_request
      when_request_runs({})
      assert_nil response_app_data
    end

    def test_doesnt_add_header_if_no_id_on_agent
      with_config( :cross_process_id => '' ) do
        when_request_runs
        assert_nil response_app_data
      end
    end

    def test_doesnt_add_header_if_config_disabled
      with_config(:"cross_application_tracer.enabled" => false, :cross_application_tracing => false) do
        when_request_runs
        assert_nil response_app_data
      end
    end

    def test_old_cat_enabled
      with_config(:"cross_application_tracer.enabled" => true) do
        assert CrossAppTracing.cross_application_tracer_enabled?
      end
    end

    def test_old_cat_disabled
      with_config(:"cross_application_tracer.enabled" => false) do
        refute CrossAppTracing.cross_application_tracer_enabled?
      end
    end

    def test_old_cat_disabled_when_better_cat_enabled
      with_config(:"cross_application_tracer.enabled" => true,
                  :"distributed_tracing.enabled"      => true) do
        refute CrossAppTracing.cross_application_tracer_enabled?
      end
    end

    def test_doesnt_add_header_if_missing_encoding_key
      with_config( :encoding_key => '' ) do
        when_request_runs
        assert_nil response_app_data
      end
    end

    def test_includes_content_length
      when_request_runs(for_id(REQUEST_CROSS_APP_ID).merge(CONTENT_LENGTH_KEY => 3000))
      assert_equal 3000, unpacked_response[CONTENT_LENGTH_POSITION]
    end

    def test_finds_content_length_from_headers
      request = { 'HTTP_CONTENT_LENGTH' => 42 }
      assert_equal(42, @monitor.send(:content_length_from_request, request))
    end

    def test_writes_attributes
      txn = when_request_runs

      assert_equal REQUEST_CROSS_APP_ID, attributes_for(txn, :intrinsic)[:client_cross_process_id]
      assert_equal REF_TRANSACTION_GUID, attributes_for(txn, :intrinsic)[:referring_transaction_guid]
    end

    def test_writes_metric
      when_request_runs

      assert_metrics_recorded(["ClientApplication/#{REQUEST_CROSS_APP_ID}/all"])
    end

    def test_doesnt_write_metric_if_id_blank
      when_request_runs(for_id(''))

      assert_metrics_recorded_exclusive(['transaction', 'Supportability/API/drop_buffered_data',
        'OtherTransactionTotalTime', 'OtherTransactionTotalTime/transaction'])
    end

    def test_setting_response_headers_freezes_transaction_name
      in_transaction do
        request = for_id(REQUEST_CROSS_APP_ID)
        @events.notify(:before_call, request)

        assert !Transaction.tl_current.name_frozen?
        @events.notify(:after_call, request, [200, @response, ''])
        assert Transaction.tl_current.name_frozen?
      end
    end

    def test_listener_in_other_thread_has_correct_txn_state
      t = Thread.new do
        in_transaction('transaction') do
          request = for_id(REQUEST_CROSS_APP_ID)

          @events.notify(:before_call, request)
          # Fake out our GUID for easier comparison in tests
          Transaction.tl_current.stubs(:guid).returns(TRANSACTION_GUID)
          @events.notify(:after_call, request, [200, @response, ''])
        end
      end

      t.join

      assert_metrics_recorded(["ClientApplication/#{REQUEST_CROSS_APP_ID}/all"])
    end

    def test_path_hash
      with_config(:app_name => 'test') do
        h0 = @monitor.path_hash('23547', 0)
        h1 = @monitor.path_hash('step1', 0)
        h2 = @monitor.path_hash('step2', h1.to_i(16))
        h3 = @monitor.path_hash('step3', h2.to_i(16))
        h4 = @monitor.path_hash('step4', h3.to_i(16))

        assert_equal("eaaec1df", h0)
        assert_equal("2e9a0b02", h1)
        assert_equal("01d3f0eb", h2)
        assert_equal("9a1b45e5", h3)
        assert_equal("e9eecfee", h4)
      end
    end

    #
    # Helpers
    #

    def when_request_runs(request=for_id(REQUEST_CROSS_APP_ID), name = 'transaction', duration = nil)
      nr_freeze_time if duration

      in_transaction(name) do |txn|
        @events.notify(:before_call, request)
        # Fake out our GUID for easier comparison in tests
        Transaction.tl_current.stubs(:guid).returns(TRANSACTION_GUID)
        advance_time duration if duration
        @events.notify(:after_call, request, [200, @response, ''])
        txn
      end
    end

    def for_id(id)
      encoded_id = id == "" ? "" : Base64.encode64(id)
      encoded_txn_info = json_dump_and_encode([ REF_TRANSACTION_GUID, false ])

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
      ::JSON.load(Base64.decode64(response_app_data))
    end

  end
end
