# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require "newrelic_rpm"
require "fake_external_server"
require "evil_server"

module HttpClientTestCases
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation,
    NewRelic::Agent::CrossAppTracing,
    MultiverseHelpers

  TRANSACTION_GUID = 'BEC1BC64675138B9'

  $fake_server = NewRelic::FakeExternalServer.new
  $fake_secure_server = NewRelic::FakeSecureExternalServer.new

  setup_and_teardown_agent(
    :"cross_application_tracer.enabled" => false,
    :cross_process_id => "269975#22824",
    :encoding_key => "gringletoes",
    :trusted_account_ids => [269975]
  )

  def after_setup
    $fake_server.reset
    $fake_server.run

    $fake_secure_server.reset
    $fake_secure_server.run

    NewRelic::Agent.instance.events.notify(:initial_configuration_complete)
    NewRelic::Agent::CrossAppTracing.instance_variable_set(:@obfuscator, nil)
  end

  # Helpers to support shared tests

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

    assert_implements req, :type
    assert_implements req, :host
    assert_implements req, :host_from_header
    assert_implements req, :method
    assert_implements req, :[], "foo"
    assert_implements req, :[]=, "foo", "bar"
    assert_implements req, :uri
  end

  def test_validate_response_wrapper
    res = response_instance

    assert_implements res, :get_status_code
    assert_implements res, :[], "foo"
    assert_implements res, :to_hash
  end

  # This test is early warning an HTTP client's library
  # has made breaking changes on their Response objects
  def test_status_code_is_present
    res = get_wrapped_response(default_url)

    assert_equal 200, res.status_code
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
    res = nil
    in_transaction { res = get_response }

    assert_match %r{<head>}i, body(res)
    assert_externals_recorded_for("localhost", "GET")
  end

  # Although rare, some clients do explicitly set the "host" header on their
  # http requests. Respect that rather than the host IP on the request if so.
  #
  # https://github.com/newrelic/newrelic-ruby-agent/pull/124
  def test_get_with_host_header
    uri = default_uri
    uri.host = '127.0.0.1'
    res = nil

    in_transaction do
      res = get_response(uri.to_s, 'Host' => 'test.local')
    end

    assert_match %r{<head>}i, body(res)
    assert_externals_recorded_for("test.local", "GET")
  end

  def test_get_with_host_header_lowercase
    uri = default_uri
    uri.host = '127.0.0.1'
    res = nil

    in_transaction do
      res = get_response(uri.to_s, 'host' => 'test.local')
    end

    assert_match %r{<head>}i, body(res)
    assert_externals_recorded_for("test.local", "GET")
  end

  # Only some HTTP clients support explicit connection reuse, so this test
  # checks whether the host responds to get_response_multi before executing.
  def test_get_with_reused_connection
    if self.respond_to?(:get_response_multi)
      n = 2
      responses = nil

      in_transaction do
        responses = get_response_multi(default_url, n)
      end

      responses.each do |res|
        assert_match %r{<head>}i, body(res)
      end

      expected = {:call_count => n}

      assert_externals_recorded_for("localhost", "GET", :counts => expected)
    end
  end

  def test_background
    res = nil

    perform_action_with_newrelic_trace(:name => "task", :category => :task) do
      res = get_response
    end

    assert_match %r{<head>}i, body(res)
    assert_externals_recorded_for("localhost", "GET")
    assert_metrics_recorded([
      ["External/localhost/#{client_name}/GET", "OtherTransaction/Background/#{self.class.name}/task"],
      "OtherTransaction/Background/#{self.class.name}/task",
      "OtherTransaction/Background/all",
      "OtherTransaction/all"
    ])
  end

  def test_transactional_metrics
    res = nil

    perform_action_with_newrelic_trace(:name => "task") do
      res = get_response
    end

    assert_match %r{<head>}i, body(res)
    assert_externals_recorded_for("localhost", "GET", :transaction_type => "Web")
    assert_metrics_recorded([
      "Controller/#{self.class.name}/task"
    ])

    assert_metrics_not_recorded([
      "External/allOther"
    ])
  end

  def test_transactional_traces_nodes
    perform_action_with_newrelic_trace(:name => "task") do
      get_response
    end

    last_node = find_last_transaction_node()

    assert_equal "External/localhost/#{client_name}/GET", last_node.metric_name
  end

  def test_ignore
    in_transaction do
      NewRelic::Agent.disable_all_tracing do
        post_response
      end
    end

    assert_metrics_recorded([])
  end

  def test_head
    in_transaction { head_response }

    assert_externals_recorded_for("localhost", "HEAD")
  end

  def test_post
    in_transaction { post_response }

    assert_externals_recorded_for("localhost", "POST")
  end

  def test_put
    in_transaction { put_response }

    assert_externals_recorded_for("localhost", "PUT")
  end

  def test_delete
    in_transaction { delete_response }

    assert_externals_recorded_for("localhost", "DELETE")
  end

  if defined?(::Addressable)
    def test_url_not_supported_by_stdlib_uri
      res = nil
      in_transaction do
        res = get_response("#{protocol}://foo:^password*12@localhost:#{server.port}/status")
      end

      assert_match %r{<head>}i, body(res)
      assert_externals_recorded_for("localhost", "GET")
    end
  end

  # When an http call is made, the agent should add a request header named
  # X-NewRelic-ID with a value equal to the encoded cross_app_id.

  def test_adds_a_request_header_to_outgoing_requests_if_xp_enabled
    NewRelic::Agent::Agent.any_instance.stubs(:connected?).returns(true)
    with_config(:"cross_application_tracer.enabled" => true, :'distributed_tracing.enabled' => false) do
      in_transaction { get_response }

      assert_equal "VURQV1BZRkZdXUFT", server.requests.last["HTTP_X_NEWRELIC_ID"]
    end
    NewRelic::Agent::Agent.any_instance.unstub(:connected?)
  end

  def test_adds_a_request_header_to_outgoing_requests_if_old_xp_config_is_present
    NewRelic::Agent::Agent.any_instance.stubs(:connected?).returns(true)
    with_config(:cross_application_tracing => true, :'distributed_tracing.enabled' => false) do
      in_transaction { get_response }

      assert_equal "VURQV1BZRkZdXUFT", server.requests.last["HTTP_X_NEWRELIC_ID"]
    end
    NewRelic::Agent::Agent.any_instance.unstub(:connected?)
  end

  def test_adds_newrelic_transaction_header
    NewRelic::Agent::Agent.any_instance.stubs(:connected?).returns(true)
    with_config(:cross_application_tracing => true, :'distributed_tracing.enabled' => false) do
      guid = nil
      path_hash = nil
      in_transaction do |txn|
        guid = txn.guid
        path_hash = txn.distributed_tracer.cat_path_hash
        get_response
      end

      transaction_data = server.requests.last["HTTP_X_NEWRELIC_TRANSACTION"]

      refute_empty(transaction_data)

      decoded = decode_payload(transaction_data)

      assert_equal(guid, decoded[0])
      refute(decoded[1])
      assert_equal(guid, decoded[2])
      assert_equal(path_hash, decoded[3])
    end
    NewRelic::Agent::Agent.any_instance.unstub(:connected?)
  end

  def test_agent_doesnt_add_a_request_header_to_outgoing_requests_if_xp_disabled
    in_transaction { get_response }

    refute server.requests.last.keys.any? { |k| k.include?('NEWRELIC_ID') }
  end

  def test_agent_doesnt_add_a_request_header_if_empty_cross_process_id
    with_config(:'cross_application_tracer.enabled' => true,
      :'distributed_tracing.enabled' => false,
      :cross_process_id => "") do
      in_transaction { get_response }

      refute server.requests.last.keys.any? { |k| k.include?('NEWRELIC_ID') }
    end
  end

  def test_agent_doesnt_add_a_request_header_if_empty_encoding_key
    with_config(
      :'cross_application_tracer.enabled' => true,
      :'distributed_tracing.enabled' => false,
      :encoding_key => ""
    ) do
      in_transaction { get_response }

      refute server.requests.last.keys.any? { |k| k.include?('NEWRELIC_ID') }
    end
  end

  def test_instrumentation_with_crossapp_enabled_records_normal_metrics_if_no_header_present
    $fake_server.override_response_headers('X-NewRelic-App-Data' => '')

    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction("test") do
        get_response
      end
    end

    assert_externals_recorded_for("localhost", "GET")
    assert_metrics_recorded([["External/localhost/#{client_name}/GET", "test"]])
  end

  def test_instrumentation_with_crossapp_disabled_records_normal_metrics_even_if_header_is_present
    $fake_server.override_response_headers('X-NewRelic-App-Data' =>
      make_app_data_payload("18#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID))

    in_transaction("test") do
      get_response
    end

    assert_externals_recorded_for("localhost", "GET")
    assert_metrics_recorded([["External/localhost/#{client_name}/GET", "test"]])
  end

  def test_instrumentation_with_crossapp_enabled_records_crossapp_metrics_if_header_present
    $fake_server.override_response_headers('X-NewRelic-App-Data' =>
      make_app_data_payload("18#1884", "txn-name", 2, 8, 0, TRANSACTION_GUID))

    with_config(:"cross_application_tracer.enabled" => true, :'distributed_tracing.enabled' => false) do
      in_transaction("test") do
        get_response
      end
    end

    last_node = find_last_transaction_node()

    assert_includes last_node.params.keys, :transaction_guid
    assert_equal TRANSACTION_GUID, last_node.params[:transaction_guid]

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
    $fake_server.override_response_headers('X-NewRelic-App-Data' =>
      make_app_data_payload("12#1114", "世界線航跡蔵", 18.0, 88.1, 4096, TRANSACTION_GUID))

    with_config(:"cross_application_tracer.enabled" => true, :'distributed_tracing.enabled' => false) do
      in_transaction("test") do
        get_response
      end
    end

    last_node = find_last_transaction_node()

    assert_includes last_node.params.keys, :transaction_guid
    assert_equal TRANSACTION_GUID, last_node.params[:transaction_guid]

    assert_metrics_recorded([
      "External/all",
      "External/allOther",
      "ExternalApp/localhost/12#1114/all",
      "External/localhost/all",
      "ExternalTransaction/localhost/12#1114/世界線航跡蔵",
      ["ExternalTransaction/localhost/12#1114/世界線航跡蔵", "test"]
    ])
  end

  def test_crossapp_metrics_ignores_crossapp_header_with_malformed_cross_process_id
    $fake_server.override_response_headers('X-NewRelic-App-Data' =>
      make_app_data_payload("88#88#88", "invalid", 1, 2, 4096, TRANSACTION_GUID))

    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction("test") do
        get_response
      end
    end

    assert_externals_recorded_for("localhost", "GET")
    assert_metrics_recorded([["External/localhost/#{client_name}/GET", "test"]])
  end

  def test_doesnt_affect_the_request_if_an_exception_is_raised_while_setting_up_tracing
    res = nil
    NewRelic::Agent.instance.stats_engine.stubs(:push_scope)
      .raises(NoMethodError, "undefined method `push_scope'")

    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction { res = get_response }
    end

    assert_equal NewRelic::FakeExternalServer::STATUS_MESSAGE, body(res)
  end

  def test_doesnt_affect_the_request_if_an_exception_is_raised_while_finishing_tracing
    res = nil
    NewRelic::Agent.instance.stats_engine.stubs(:pop_scope)
      .raises(NoMethodError, "undefined method `pop_scope'")

    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction { res = get_response }
    end

    assert_equal NewRelic::FakeExternalServer::STATUS_MESSAGE, body(res)
  end

  def test_doesnt_misbehave_when_transaction_tracing_is_disabled
    # The error should have any other consequence other than logging the error, so
    # this will capture logs
    logger = NewRelic::Agent::MemoryLogger.new
    NewRelic::Agent.logger = logger

    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction { get_response }
    end

    refute_match(/undefined method `.*" for nil:NilClass/i,
      logger.messages.flatten.map { |log| log.to_s }.join(" "))
  end

  def test_includes_full_url_in_transaction_trace
    full_url = "#{default_url}?foo=bar#fragment"
    in_transaction do
      get_response(full_url)
    end

    last_node = find_last_transaction_node()
    filtered_uri = default_url

    assert_equal filtered_uri, last_node.params[:uri]
  end

  # https://newrelic.atlassian.net/browse/RUBY-1244
  def test_failure_in_our_start_code_still_records_externals
    # Fake a failure in our start-up code...
    ::JSON.stubs(:dump).raises("Boom!")

    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction { get_response }
    end

    assert_externals_recorded_for("localhost", "GET")
  end

  # https://newrelic.atlassian.net/browse/RUBY-1244
  def test_failure_to_add_tt_node_doesnt_append_params_to_wrong_node
    # Fake a failure in our start-up code...
    ::JSON.stubs(:dump).raises("Boom!")

    in_transaction do
      with_config(:"cross_application_tracer.enabled" => true) do
        get_response
      end
    end

    last_node = find_last_transaction_node()
    unless last_node.metric_name.start_with?("External")
      refute last_node.params.key?(:uri)
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
        rescue
          # it's expected that this will raise for some HTTP libraries (e.g.
          # Net::HTTP). we unfortunately don't know the exact exception class
          # across all libraries
        end
      end

      last_node = find_last_transaction_node()

      assert_equal("External/localhost/#{client_name}/GET", last_node.metric_name)

      evil_server.stop
    end
  end

  def test_raw_synthetics_header_is_passed_along_if_present
    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction do
        NewRelic::Agent::Tracer.current_transaction.raw_synthetics_header = "boo"

        get_response

        assert_equal "boo", server.requests.last["HTTP_X_NEWRELIC_SYNTHETICS"]
      end
    end
  end

  def test_no_raw_synthetics_header_if_not_present
    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction do
        get_response

        refute_includes server.requests.last.keys, "HTTP_X_NEWRELIC_SYNTHETICS"
      end
    end
  end

  def test_raw_synthetics_header_is_passed_along_when_cat_disabled
    with_config(:"cross_application_tracer.enabled" => false) do
      in_transaction do
        NewRelic::Agent::Tracer.current_transaction.raw_synthetics_header = "boo"

        get_response

        assert_equal "boo", server.requests.last["HTTP_X_NEWRELIC_SYNTHETICS"]
      end
    end
  end

  load_cross_agent_test("cat_map").each do |test_case|
    # Test cases that don't involve outgoing calls are done elsewhere
    if test_case['outboundRequests']
      define_method("test_#{test_case['name']}") do
        NewRelic::Agent::Agent.any_instance.stubs(:connected?).returns(true)
        config = {
          :app_name => test_case['appName'],
          :'cross_application_tracer.enabled' => true,
          :'distributed_tracing.enabled' => false,
          :'disable_all_tracing.enabled' => false
        }
        with_config(config) do
          NewRelic::Agent.instance.events.notify(:initial_configuration_complete)

          in_transaction do |txn|
            txn_info = test_case['inboundPayload']
            payload = NewRelic::Agent::CrossAppPayload.new('someId', txn, txn_info)
            txn.distributed_tracer.cross_app_payload = payload
            stub_transaction_guid(test_case['transactionGuid'])
            test_case['outboundRequests'].each do |req|
              set_explicit_transaction_name(req['outboundTxnName'])
              get_response

              outbound_payload = server.requests.last["HTTP_X_NEWRELIC_TRANSACTION"]
              decoded_outbound_payload = decode_payload(outbound_payload)

              assert_equal(req['expectedOutboundPayload'], decoded_outbound_payload)
            end
            set_explicit_transaction_name(test_case['transactionName'])
          end
        end

        event = get_last_analytics_event

        assert_event_attributes(
          event,
          test_case['name'],
          test_case['expectedIntrinsicFields'],
          test_case['nonExpectedIntrinsicFields']
        )
        NewRelic::Agent::Agent.any_instance.unstub(:connected?)
      end
    end
  end

  # These tests only cover receiving, validating, and passing on the synthetics
  # request header to any outgoing HTTP requests. They do *not* cover attaching
  # of appropriate data to analytics events or transaction traces.
  #
  # The tests in agent_only/synthetics_test.rb cover that.
  load_cross_agent_test('synthetics/synthetics').each do |test|
    define_method("test_synthetics_http_#{test['name']}") do
      config = {
        :encoding_key => test['settings']['agentEncodingKey'],
        :trusted_account_ids => test['settings']['trustedAccountIds'],
        :'cross_application_tracer.enabled' => true,
        :'distributed_tracing.enabled' => false
      }

      with_config config do
        NewRelic::Agent.instance.events.notify(:initial_configuration_complete)

        fake_rack_env = {}
        test['inputObfuscatedHeader'].each do |key, value|
          fake_rack_env[http_header_name_to_rack_key(key)] = value
        end

        in_transaction do
          NewRelic::Agent.agent.events.notify(:before_call, fake_rack_env)
          get_response

          last_outbound_request = server.requests.last
          header_specs = test['outputExternalRequestHeader']

          header_specs['expectedHeader'].each do |key, value|
            expected_key = http_header_name_to_rack_key(key)

            assert_equal(value, last_outbound_request[expected_key])
          end

          header_specs['nonExpectedHeader'].each do |key|
            non_expected_key = http_header_name_to_rack_key(key)

            refute_includes(last_outbound_request.keys, non_expected_key)
          end
        end
      end
    end
  end

  def http_header_name_to_rack_key(name)
    "HTTP_" + name.upcase.tr('-', '_')
  end

  def make_app_data_payload(*args)
    obfuscator = NewRelic::Agent::Obfuscator.new('gringletoes')
    return obfuscator.obfuscate(args.to_json)
  end

  def decode_payload(payload)
    obfuscator = NewRelic::Agent::Obfuscator.new('gringletoes')
    ::JSON.load(obfuscator.deobfuscate(payload))
  end

  def set_explicit_transaction_name(name)
    parts = name.split("/")
    category = parts.shift
    NewRelic::Agent.set_transaction_name(parts.join('/'), :category => category)
  end

  def assert_externals_recorded_for(host, meth, opts = {})
    txn_type = opts.fetch(:transaction_type, "Other")
    counts = opts.fetch(:counts, nil)

    if counts.nil?
      assert_metrics_recorded([
        "External/all",
        "External/all#{txn_type}",
        "External/#{host}/#{client_name}/#{meth}",
        "External/#{host}/all"
      ])
    else
      assert_metrics_recorded(
        "External/all" => counts,
        "External/all#{txn_type}" => counts,
        "External/#{host}/#{client_name}/#{meth}" => counts,
        "External/#{host}/all" => counts
      )
    end
  end

  def test_noticed_error_at_segment_and_txn_on_error
    txn = nil
    begin
      in_transaction do |ext_txn|
        txn = ext_txn
        simulate_error_response
      end
    rescue StandardError => e
      # NOP -- allowing span and transaction to notice error
    end

    assert_segment_noticed_error txn, /GET$/, timeout_error_class.name, /timeout|couldn't connect/i
    assert_transaction_noticed_error txn, timeout_error_class.name
  end

  def test_noticed_error_only_at_segment_on_error
    txn = nil
    in_transaction do |ext_txn|
      begin
        txn = ext_txn
        simulate_error_response
      rescue StandardError => e
        # NOP -- allowing ONLY span to notice error
      end
    end

    assert_segment_noticed_error txn, /GET$/, timeout_error_class.name, /timeout|couldn't connect/i
    refute_transaction_noticed_error txn, timeout_error_class.name
  end

  def simulate_server_error(server_class, port)
    server = server_class.new(port)
    server.run
    get_response("http://localhost:#{port}")
  ensure
    server.stop
  end

  def test_noticed_forbidden_error
    txn = nil
    response = nil
    in_transaction do |ext_txn|
      begin
        txn = ext_txn
        response = simulate_server_error(NewRelic::FakeForbiddenServer, 4403)
      rescue StandardError => e
        # NOP
      end
    end

    segment = txn.segments.detect { |s| s.name =~ /GET$/ }

    assert segment, "Expected a .../GET Segment for #{client_name} HTTP Client instrumentation."

    assert_equal 403, segment.http_status_code
  end

  def test_noticed_internal_server_error
    txn = nil
    response = nil
    in_transaction do |ext_txn|
      begin
        txn = ext_txn
        response = simulate_server_error(NewRelic::FakeInternalErrorServer, 5500)
      rescue StandardError => e
        # NOP
      end
    end

    segment = txn.segments.detect { |s| s.name =~ /GET$/ }

    assert segment, "Expected a .../GET Segment for #{client_name} HTTP Client instrumentation."

    assert_equal 500, segment.http_status_code
  end
end
