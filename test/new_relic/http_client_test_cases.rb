# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "newrelic_rpm"
require "fake_external_server"
require 'mocha'

module HttpClientTestCases
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation,
          NewRelic::Agent::CrossAppMonitor::EncodingFunctions,
          NewRelic::Agent::CrossAppTracing

  TRANSACTION_GUID = 'BEC1BC64675138B9'

  $fake_server = NewRelic::FakeExternalServer.new

  def setup
    $fake_server.reset
    $fake_server.run

    NewRelic::Agent.manual_start(
      :"cross_application_tracer.enabled" => false,
      :cross_process_id                   => "269975#22824",
      :encoding_key                       => "gringletoes",
      :trusted_account_ids                => [269975]
    )

    NewRelic::Agent.instance.reset_stats

    NewRelic::Agent.instance.events.clear
    NewRelic::Agent.instance.cross_app_monitor.register_event_listeners
    NewRelic::Agent.instance.events.notify(:finished_configuring)

    @nr_header = nil
    NewRelic::Agent.instance.events.subscribe(:after_call) do |_, (_, headers, _)|
      headers[ NR_APPDATA_HEADER ] = @nr_header unless @nr_header.nil?
    end

    @engine = NewRelic::Agent.instance.stats_engine
    NewRelic::Agent::TransactionInfo.get.guid = TRANSACTION_GUID
  end

  def teardown
    NewRelic::Agent.instance.transaction_sampler.reset!
    Thread::current[:newrelic_scope_stack] = nil
    NewRelic::Agent.instance.stats_engine.end_transaction
  end

  # Helpers to support shared tests

  def default_url
    "http://localhost:#{$fake_server.port}/status"
  end

  def default_uri
    URI.parse(default_url)
  end

  def body(res)
    res.body
  end

  # Tests

  def test_validate_request_wrapper
    req = request_instance
    req.respond_to?(:type)
    req.respond_to?(:host)
    req.respond_to?(:method)
    req.respond_to?(:[])
    req.respond_to?(:[]=)
    req.respond_to?(:uri)
  end

  def test_validate_response_wrapper
    res = response_instance
    res.respond_to?(:[])
    res.respond_to?(:to_hash)
  end

  def test_get
    res = get_response

    assert_match %r/<head>/i, body(res)
    assert_metrics_recorded([
      "External/all",
      "External/localhost/#{client_name}/GET",
      "External/allOther",
      "External/localhost/all"
    ])
  end

  def test_background
    res = nil

    perform_action_with_newrelic_trace("task", :category => :task) do
      res = get_response
    end

    assert_match %r/<head>/i, body(res)
    assert_metrics_recorded([
      "External/all",
      "External/allOther",
      "External/localhost/all",
      "External/localhost/#{client_name}/GET",
      ["External/localhost/#{client_name}/GET", "OtherTransaction/Background/#{self.class.name}/task"],
      "OtherTransaction/Background/#{self.class.name}/task",
      "OtherTransaction/Background/all",
      "OtherTransaction/all"
    ])
  end

  def test_transactional
    res = nil

    perform_action_with_newrelic_trace("task") do
      res = get_response
    end

    assert_match %r/<head>/i, body(res)
    assert_metrics_recorded([
      "External/all",
      "External/localhost/#{client_name}/GET",
      "External/allWeb",
      "External/localhost/all",
      "Controller/#{self.class.name}/task"
    ])

    assert_metrics_not_recorded([
      "External/allOther"
    ])
  end


  def test_ignore
    in_transaction do
      NewRelic::Agent.disable_all_tracing do
        res = post_response
      end
    end

    assert_metrics_recorded([])
  end

  def test_head
    res = head_response

    assert_metrics_recorded([
      "External/all",
      "External/localhost/#{client_name}/HEAD",
      "External/allOther",
      "External/localhost/all"
    ])
  end

  def test_post
    post_response

    assert_metrics_recorded([
      "External/all",
      "External/localhost/#{client_name}/POST",
      "External/allOther",
      "External/localhost/all"
    ])
  end

  # When an http call is made, the agent should add a request header named
  # X-NewRelic-ID with a value equal to the encoded cross_app_id.

  def test_adds_a_request_header_to_outgoing_requests_if_xp_enabled
    with_config(:"cross_application_tracer.enabled" => true) do
      get_response
      assert_equal "VURQV1BZRkZdXUFT", $fake_server.requests.last["HTTP_X_NEWRELIC_ID"]
    end
  end

  def test_adds_a_request_header_to_outgoing_requests_if_old_xp_config_is_present
    with_config(:cross_application_tracing => true) do
      get_response
      assert_equal "VURQV1BZRkZdXUFT", $fake_server.requests.last["HTTP_X_NEWRELIC_ID"]
    end
  end

  def test_agent_doesnt_add_a_request_header_to_outgoing_requests_if_xp_disabled
    get_response
    assert_equal false, $fake_server.requests.last.keys.any? {|k| k =~ /NEWRELIC_ID/}
  end


  def test_instrumentation_with_crossapp_enabled_records_normal_metrics_if_no_header_present
    @nr_header = ""

    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction("test") do
        get_response
      end
    end

    assert_metrics_recorded([
      "External/all",
      "External/allOther",
      "External/localhost/all",
      "External/localhost/#{client_name}/GET",
      ["External/localhost/#{client_name}/GET", "test"]
    ])
  end

  def test_instrumentation_with_crossapp_disabled_records_normal_metrics_even_if_header_is_present
    @nr_header =
      make_app_data_payload( "18#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID )

    in_transaction("test") do
      get_response
    end

    assert_metrics_recorded([
      "External/all",
      "External/allOther",
      "External/localhost/all",
      "External/localhost/#{client_name}/GET",
       ["External/localhost/#{client_name}/GET", "test"]
    ])
  end

  def test_instrumentation_with_crossapp_enabled_records_crossapp_metrics_if_header_present
    @nr_header =
      make_app_data_payload( "18#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID )

    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction("test") do
        get_response

        last_segment = find_last_transaction_segment()
        assert_includes last_segment.params.keys, :transaction_guid
        assert_equal TRANSACTION_GUID, last_segment.params[:transaction_guid]
      end
    end

    assert_metrics_recorded([
      "External/all",
      "External/allOther",
      "ExternalApp/localhost/18#1884/all",
      "ExternalTransaction/localhost/18#1884/txn-name",
      "External/localhost/all",
      ["ExternalTransaction/localhost/18#1884/txn-name", "test"]
    ])
  end

  def test_crossapp_metrics_allow_valid_utf8_characters
    @nr_header =
      make_app_data_payload( "12#1114", "世界線航跡蔵", 18.0, 88.1, 4096, TRANSACTION_GUID )

    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction("test") do
        get_response

        last_segment = find_last_transaction_segment()
        assert_includes last_segment.params.keys, :transaction_guid
        assert_equal TRANSACTION_GUID, last_segment.params[:transaction_guid]
      end
    end

    assert_metrics_recorded([
      "External/all",
      "External/allOther",
      "ExternalApp/localhost/12#1114/all",
      "External/localhost/all",
      "ExternalTransaction/localhost/12#1114/世界線航跡蔵",
      ["ExternalTransaction/localhost/12#1114/世界線航跡蔵", "test"]
    ])
  end

  def test_crossapp_metrics_ignores_crossapp_header_with_malformed_crossprocess_id
    @nr_header =
      make_app_data_payload( "88#88#88", "invalid", 1, 2, 4096, TRANSACTION_GUID )

    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction("test") do
        get_response
      end
    end

    assert_metrics_recorded([
      "External/all",
      "External/allOther",
      "External/localhost/#{client_name}/GET",
      "External/localhost/all",
      ["External/localhost/#{client_name}/GET", "test"]
    ])
  end

  def test_doesnt_affect_the_request_if_an_exception_is_raised_while_setting_up_tracing
    res = nil
    NewRelic::Agent.instance.stats_engine.stubs( :push_scope ).
      raises( NoMethodError, "undefined method `push_scope'" )

    with_config(:"cross_application_tracer.enabled" => true) do
      assert_nothing_raised do
        res = get_response
      end
    end

    assert_equal NewRelic::FakeExternalServer::STATUS_MESSAGE, body(res)
  end

  def test_doesnt_affect_the_request_if_an_exception_is_raised_while_finishing_tracing
    res = nil
    NewRelic::Agent.instance.stats_engine.stubs( :pop_scope ).
      raises( NoMethodError, "undefined method `pop_scope'" )

    with_config(:"cross_application_tracer.enabled" => true) do
      assert_nothing_raised do
        res = get_response
      end
    end

    assert_equal NewRelic::FakeExternalServer::STATUS_MESSAGE, body(res)
  end

  def test_doesnt_misbehave_when_transaction_tracing_is_disabled
    @engine.transaction_sampler = nil

    # The error should have any other consequence other than logging the error, so
    # this will capture logs
    logger = NewRelic::Agent::MemoryLogger.new
    NewRelic::Agent.logger = logger

    with_config(:"cross_application_tracer.enabled" => true) do
      get_response
    end

    assert_no_match( /undefined method `rename_scope_segment" for nil:NilClass/i,
                     logger.messages.flatten.map {|log| log.to_s }.join(" ") )

  ensure
    @engine.transaction_sampler = NewRelic::Agent.agent.transaction_sampler
  end

  def test_includes_full_url_in_transaction_trace
    full_url = "#{default_url}?foo=bar#fragment"
    in_transaction do
      get_response(full_url)
      last_segment = find_last_transaction_segment()
      filtered_uri = default_url
      assert_equal filtered_uri, last_segment.params[:uri]
    end
  end

  def make_app_data_payload( *args )
    return obfuscate_with_key( 'gringletoes', args.to_json ).gsub( /\n/, '' ) + "\n"
  end
end

