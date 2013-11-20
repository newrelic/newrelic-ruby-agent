# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "newrelic_rpm"
require "fake_external_server"
require "evil_server"
require 'mocha'
require 'multiverse_helpers'

module HttpClientTestCases
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation,
          NewRelic::Agent::CrossAppMonitor::EncodingFunctions,
          NewRelic::Agent::CrossAppTracing,
          MultiverseHelpers

  TRANSACTION_GUID = 'BEC1BC64675138B9'

  $fake_server = NewRelic::FakeExternalServer.new
  $fake_secure_server = NewRelic::FakeSecureExternalServer.new

  setup_and_teardown_agent(
      :"cross_application_tracer.enabled" => false,
      :cross_process_id                   => "269975#22824",
      :encoding_key                       => "gringletoes",
      :trusted_account_ids                => [269975]
    )

  def after_setup
    $fake_server.reset
    $fake_server.run

    $fake_secure_server.reset
    $fake_secure_server.run

    NewRelic::Agent.instance.events.clear
    NewRelic::Agent.instance.cross_app_monitor.register_event_listeners
    NewRelic::Agent.instance.events.notify(:finished_configuring)

    @nr_header = nil
    # Don't use destructuring on result array with ignores since it fails
    # on Rubinius: https://github.com/rubinius/rubinius/issues/2678
    NewRelic::Agent.instance.events.subscribe(:after_call) do |_, result|
      headers = result[1]
      headers[ NR_APPDATA_HEADER ] = @nr_header unless @nr_header.nil?
    end

    @engine = NewRelic::Agent.instance.stats_engine
    NewRelic::Agent::TransactionState.get.request_guid = TRANSACTION_GUID
  end

  # Helpers to support shared tests

  def use_ssl
    @ssl = true
  end

  def use_ssl?
    @ssl
  end

  def server
    @ssl ? $fake_secure_server : $fake_server
  end

  def protocol
    @ssl ? "https" : "http"
  end

  def default_url
    "#{protocol}://localhost:#{server.port}/status"
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

  # Some libraries (older Typhoeus), have had odd behavior around [] for
  # missing keys. This generates log messages, although it behaves right in
  # terms of metrics, so double-check we get what we expect
  def test_request_headers_for_missing_key
    assert_nil request_instance["boo"]
  end

  def test_response_headers_for_missing_key
    assert_nil response_instance["boo"]
  end

  def test_response_wrapper_ignores_case_in_header_keys
    res = response_instance('NAMCO' => 'digdug')
    assert_equal 'digdug', res['namco']
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

  # Although rare, some clients do explicitly set the "host" header on their
  # http requests. Respect that rather than the host IP on the request if so.
  #
  # https://github.com/newrelic/rpm/pull/124
  def test_get_with_host_header
    uri = default_uri
    uri.host = '127.0.0.1'
    res = get_response(uri.to_s, 'Host' => 'test.local')

    assert_match %r/<head>/i, body(res)
    assert_metrics_recorded([
      "External/all",
      "External/test.local/#{client_name}/GET",
      "External/allOther",
      "External/test.local/all"
    ])
  end

  def test_get_with_host_header_lowercase
    uri = default_uri
    uri.host = '127.0.0.1'
    res = get_response(uri.to_s, 'host' => 'test.local')

    assert_match %r/<head>/i, body(res)
    assert_metrics_recorded([
      "External/all",
      "External/test.local/#{client_name}/GET",
      "External/allOther",
      "External/test.local/all"
    ])
  end

  # Only some HTTP clients support explicit connection reuse, so this test
  # checks whether the host responds to get_response_multi before executing.
  def test_get_with_reused_connection
    if self.respond_to?(:get_response_multi)
      n = 2
      responses = get_response_multi(default_url, n)

      responses.each do |res|
        assert_match %r/<head>/i, body(res)
      end

      expected = { :call_count => n }
      assert_metrics_recorded(
        "External/all" => expected,
        "External/localhost/#{client_name}/GET" => expected,
        "External/allOther" => expected,
        "External/localhost/all" => expected
      )
    end
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

  def test_transactional_metrics
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


  def test_transactional_traces_nodes
    perform_action_with_newrelic_trace("task") do
      res = get_response

      last_segment = find_last_transaction_segment()
      assert_equal "External/localhost/#{client_name}/GET", last_segment.metric_name
    end
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

  def test_put
    put_response

    assert_metrics_recorded([
      "External/all",
      "External/localhost/#{client_name}/PUT",
      "External/allOther",
      "External/localhost/all"
    ])
  end

  def test_delete
    delete_response

    assert_metrics_recorded([
      "External/all",
      "External/localhost/#{client_name}/DELETE",
      "External/allOther",
      "External/localhost/all"
    ])
  end

  # When an http call is made, the agent should add a request header named
  # X-NewRelic-ID with a value equal to the encoded cross_app_id.

  def test_adds_a_request_header_to_outgoing_requests_if_xp_enabled
    with_config(:"cross_application_tracer.enabled" => true) do
      get_response
      assert_equal "VURQV1BZRkZdXUFT", server.requests.last["HTTP_X_NEWRELIC_ID"]
    end
  end

  def test_adds_a_request_header_to_outgoing_requests_if_old_xp_config_is_present
    with_config(:cross_application_tracing => true) do
      get_response
      assert_equal "VURQV1BZRkZdXUFT", server.requests.last["HTTP_X_NEWRELIC_ID"]
    end
  end

  def test_agent_doesnt_add_a_request_header_to_outgoing_requests_if_xp_disabled
    get_response
    assert_equal false, server.requests.last.keys.any? {|k| k =~ /NEWRELIC_ID/}
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
      res = get_response
    end

    assert_equal NewRelic::FakeExternalServer::STATUS_MESSAGE, body(res)
  end

  def test_doesnt_affect_the_request_if_an_exception_is_raised_while_finishing_tracing
    res = nil
    NewRelic::Agent.instance.stats_engine.stubs( :pop_scope ).
      raises( NoMethodError, "undefined method `pop_scope'" )

    with_config(:"cross_application_tracer.enabled" => true) do
      res = get_response
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

    refute_match( /undefined method `rename_scope_segment" for nil:NilClass/i,
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

  def test_still_records_tt_node_when_request_fails
    # This test does not work on older versions of Typhoeus, because the
    # on_complete callback is not reliably invoked. That said, it's a corner
    # case, and the failure mode is just that you lose tracing for the one
    # transaction in which the error occurs. That, coupled with the fact that
    # fixing it for old versions of Typhoeus would require large changes to
    # the instrumentation, makes us say 'meh'.
    is_typhoeus = (client_name == 'Typhoeus')
    if !is_typhoeus || (is_typhoeus && Typhoeus::VERSION >= "0.5.4")
      evil_server = NewRelic::EvilServer.new
      evil_server.start

      in_transaction do
        begin
          get_response("http://localhost:#{evil_server.port}")
        rescue => e
          # it's expected that this will raise for some HTTP libraries (e.g.
          # Net::HTTP). we unfortunately don't know the exact exception class
          # across all libraries
        end

        last_segment = find_last_transaction_segment()
        assert_equal("External/localhost/#{client_name}/GET", last_segment.metric_name)
      end

      evil_server.stop
    end
  end

  def make_app_data_payload( *args )
    return obfuscate_with_key( 'gringletoes', args.to_json ).gsub( /\n/, '' ) + "\n"
  end

end
