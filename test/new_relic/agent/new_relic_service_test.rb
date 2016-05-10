# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'cgi'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/agent/commands/thread_profiler_session'

class NewRelicServiceTest < Minitest::Test
  def setup
    @server = NewRelic::Control::Server.new('somewhere.example.com', 30303)
    @service = NewRelic::Agent::NewRelicService.new('license-key', @server)

    @http_handle = create_http_handle
    @http_handle.respond_to(:get_redirect_host, 'localhost')
    connect_response = {
      'config' => 'some config directives',
      'agent_run_id' => 1
    }
    @http_handle.respond_to(:connect, connect_response)

    @service.stubs(:create_http_connection).returns(@http_handle)
  end

  def create_http_handle(name='connection')
    HTTPHandle.new(name)
  end

  def test_session_handles_timeouts_opening_connection_gracefully
    @http_handle.stubs(:start).raises(Timeout::Error)

    block_ran = false

    assert_raises(::NewRelic::Agent::ServerConnectionException) do
      @service.session do
        block_ran = true
      end
    end

    assert(!block_ran, "Expected block passed to #session to have not run")
  end

  def test_session_block_reuses_http_handle_with_aggressive_keepalive_off
    handle1 = create_http_handle
    handle2 = create_http_handle
    @service.stubs(:create_http_connection).returns(handle1, handle2)

    block_ran = false
    with_config(:aggressive_keepalive => false) do
      @service.session do
        block_ran = true
        assert(@service.http_connection)

        # check we get the same object back each time we call http_connection in the block
        assert_equal(@service.http_connection.object_id, handle1.object_id)
        assert_equal(@service.http_connection.object_id, handle1.object_id)
      end
    end
    assert(block_ran)

    assert_equal([:start, :finish], handle1.calls)
    assert_equal([],                handle2.calls)
  end

  def test_multiple_http_handles_are_used_outside_session_block
    handle1 = create_http_handle
    handle2 = create_http_handle
    @service.stubs(:create_http_connection).returns(handle1, handle2)
    assert_equal(@service.http_connection.object_id, handle1.object_id)
    assert_equal(@service.http_connection.object_id, handle2.object_id)
  end

  # Calling start on a Net::HTTP instance results in connection keep-alive
  # being used, which means that the connection won't be automatically closed
  # once a request is issued. For calls to the service outside of a session
  # block (/get_redirect_host and /connect, namely), we actually want the
  # connection to only be used for a single request.
  def test_connections_not_explicitly_started_outside_session_block
    @http_handle.respond_to(:foo, ['blah'])

    @service.send(:invoke_remote, :foo, ['payload'])

    assert_equal([:request], @http_handle.calls)
  end

  def test_session_starts_and_finishes_http_session_with_aggressive_keepalive_off
    block_ran = false

    with_config(:aggressive_keepalive => false) do
      @service.session do
        block_ran = true
      end
    end

    assert(block_ran)
    assert_equal([:start, :finish], @http_handle.calls)
  end

  def test_session_does_not_close_connection_if_aggressive_keepalive_on
    calls_to_block = 0

    with_config(:aggressive_keepalive => true) do
      2.times do
        @service.session { calls_to_block += 1 }
      end
    end

    assert_equal(2, calls_to_block)
    assert_equal([:start], @http_handle.calls)
  end

  def test_requests_after_connection_failure_in_session_still_use_connection_caching
    conn0 = create_http_handle('first connection')
    conn1 = create_http_handle('second connection')
    conn2 = create_http_handle('third connection')
    @service.stubs(:create_http_connection).returns(conn0, conn1, conn2)

    rsp_payload = ['ok']

    conn0.respond_to(:foo, EOFError.new)
    conn1.respond_to(:foo, rsp_payload)
    conn1.respond_to(:bar, rsp_payload)
    conn1.respond_to(:baz, rsp_payload)

    @service.session do
      @service.send(:invoke_remote, :foo, ['payload'])
      @service.send(:invoke_remote, :bar, ['payload'])
      @service.send(:invoke_remote, :baz, ['payload'])
    end

    assert_equal([:start, :request, :finish], conn0.calls)
    assert_equal([:start, :request, :request, :request], conn1.calls)
    assert_equal([], conn2.calls)
  end

  def test_repeated_connection_failures
    conn0 = create_http_handle('first connection')
    conn1 = create_http_handle('second connection')
    conn2 = create_http_handle('third connection')
    @service.stubs(:create_http_connection).returns(conn0, conn1, conn2)

    rsp_payload = ['ok']

    conn0.respond_to(:foo, EOFError.new)
    conn1.respond_to(:foo, EOFError.new)
    conn2.respond_to(:bar, rsp_payload)
    conn2.respond_to(:baz, rsp_payload)

    @service.session do
      assert_raises(::NewRelic::Agent::ServerConnectionException) do
        @service.send(:invoke_remote, :foo, ['payload'])
      end
      @service.send(:invoke_remote, :bar, ['payload'])
      @service.send(:invoke_remote, :baz, ['payload'])
    end

    assert_equal([:start, :request, :finish], conn0.calls)
    assert_equal([:start, :request, :finish], conn1.calls)
    assert_equal([:start, :request, :request], conn2.calls)
  end

  def test_repeated_connection_failures_on_reconnect
    conn0 = create_http_handle('first connection')
    conn1 = create_http_handle('second connection')
    conn2 = create_http_handle('third connection')

    conn0.respond_to(:foo, EOFError.new)
    conn1.expects(:start).once.raises(EOFError.new)
    conn2.expects(:start).never

    @service.stubs(:create_http_connection).returns(conn0, conn1, conn2)

    assert_raises(::NewRelic::Agent::ServerConnectionException) do
      @service.session do
        @service.send(:invoke_remote, :foo, ['payload'])
      end
    end
  end

  def test_repeated_connection_failures_outside_session
    conn0 = create_http_handle('first connection')
    conn1 = create_http_handle('second connection')
    conn2 = create_http_handle('third connection')

    conn0.respond_to(:foo, EOFError.new)
    conn1.respond_to(:foo, EOFError.new)

    @service.stubs(:create_http_connection).returns(conn0, conn1, conn2)

    assert_raises(::NewRelic::Agent::ServerConnectionException) do
      @service.send(:invoke_remote, :foo, ['payload'])
    end

    assert_equal([:request], conn0.calls)
    assert_equal([:request], conn1.calls)
    assert_equal([],         conn2.calls)
  end

  def test_cert_file_path
    assert @service.cert_file_path
    assert_equal File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'cert', 'cacert.pem')), @service.cert_file_path
  end

  def test_cert_file_path_uses_path_from_config
    fake_cert_path = '/certpath/cert.pem'
    with_config(:ca_bundle_path => fake_cert_path) do
      assert_equal @service.cert_file_path, fake_cert_path
    end
  end

  def test_initialize_uses_correct_license_key_settings
    with_config(:license_key => 'abcde') do
      service = NewRelic::Agent::NewRelicService.new
      assert_equal 'abcde', service.instance_variable_get(:@license_key)
    end
  end

  def test_connect_sets_agent_id_and_config_data
    response = @service.connect
    assert_equal 1, response['agent_run_id']
    assert_equal 'some config directives', response['config']
  end

  def test_connect_sets_redirect_host
    assert_equal 'somewhere.example.com', @service.collector.name
    @service.connect
    assert_equal 'localhost', @service.collector.name
  end

  def test_connect_uses_proxy_collector_if_no_redirect_host
    @http_handle.reset
    @http_handle.respond_to(:get_redirect_host, nil)
    @http_handle.respond_to(:connect, 'agent_run_id' => 1)

    @service.connect
    assert_equal 'somewhere.example.com', @service.collector.name
  end

  def test_connect_sets_agent_id
    @http_handle.reset
    @http_handle.respond_to(:get_redirect_host, 'localhost')
    @http_handle.respond_to(:connect, 'agent_run_id' => 666)

    @service.connect
    assert_equal 666, @service.agent_id
  end

  def test_get_redirect_host
    assert_equal 'localhost', @service.get_redirect_host
  end

  def test_shutdown
    @service.agent_id = 666
    @http_handle.respond_to(:shutdown, 'shut this bird down')
    response = @service.shutdown(Time.now)
    assert_equal 'shut this bird down', response
  end

  def test_should_not_shutdown_if_never_connected
    @http_handle.respond_to(:shutdown, 'shut this bird down')
    response = @service.shutdown(Time.now)
    assert_nil response
  end

  def test_metric_data
    dummy_rsp = 'met rick date uhh'
    @http_handle.respond_to(:metric_data, dummy_rsp)
    stats_hash = NewRelic::Agent::StatsHash.new
    stats_hash.harvested_at = Time.now
    response = @service.metric_data(stats_hash)

    assert_equal 4, @http_handle.last_request_payload.size
    assert_equal dummy_rsp, response
  end

  def test_metric_data_sends_harvest_timestamps
    @http_handle.respond_to(:metric_data, 'foo')

    t0 = freeze_time
    stats_hash = NewRelic::Agent::StatsHash.new
    stats_hash.harvested_at = Time.now

    @service.metric_data(stats_hash)
    payload = @http_handle.last_request_payload
    _, last_harvest_timestamp, harvest_timestamp, _ = payload
    assert_in_delta(t0.to_f, harvest_timestamp, 0.0001)

    t1 = advance_time(10)
    stats_hash.harvested_at = t1

    @service.metric_data(stats_hash)
    payload = @http_handle.last_request_payload
    _, last_harvest_timestamp, harvest_timestamp, _ = payload
    assert_in_delta(t1.to_f, harvest_timestamp, 0.0001)
    assert_in_delta(t0.to_f, last_harvest_timestamp, 0.0001)
  end

  def test_metric_data_harvest_time_based_on_stats_hash_creation
    t0 = freeze_time
    dummy_rsp = 'met rick date uhh'
    @http_handle.respond_to(:metric_data, dummy_rsp)

    advance_time 10
    stats_hash = NewRelic::Agent::StatsHash.new
    advance_time 1
    stats_hash.harvested_at = Time.now

    @service.metric_data(stats_hash)

    timeslice_start = @http_handle.last_request_payload[1]
    assert_in_delta(timeslice_start, t0.to_f + 10, 0.0001)
  end

  def test_error_data
    @http_handle.respond_to(:error_data, 'too human')
    response = @service.error_data([])
    assert_equal 'too human', response
  end

  def test_transaction_sample_data
    @http_handle.respond_to(:transaction_sample_data, 'MPC1000')
    response = @service.transaction_sample_data([])
    assert_equal 'MPC1000', response
  end

  def test_sql_trace_data
    @http_handle.respond_to(:sql_trace_data, 'explain this')
    response = @service.sql_trace_data([])
    assert_equal 'explain this', response
  end

  def test_analytic_event_data
    @http_handle.respond_to(:analytic_event_data, 'some analytic events')
    response = @service.analytic_event_data([{}, []])
    assert_equal 'some analytic events', response
  end

  def error_event_data
    @http_handle.respond_to(:error_event_data, 'some error events')
    response = @service.error_event_data([{}, []])
    assert_equal 'some error events', response
  end

  # Although thread profiling is only available in some circumstances, the
  # service communication doesn't care about that at all
  def test_profile_data
    @http_handle.respond_to(:profile_data, 'profile' => 123)
    response = @service.profile_data([])
    assert_equal({ "profile" => 123 }, response)
  end

  def test_profile_data_does_not_normalize_encodings
    @http_handle.respond_to(:profile_data, nil)
    NewRelic::JSONWrapper.expects(:normalize).never
    @service.profile_data([])
  end

  def test_get_agent_commands
    @service.agent_id = 666
    @http_handle.respond_to(:get_agent_commands, [1,2,3])

    response = @service.get_agent_commands
    assert_equal [1,2,3], response
  end

  def test_get_agent_commands_with_no_response
    @service.agent_id = 666
    @http_handle.respond_to(:get_agent_commands, nil)

    response = @service.get_agent_commands
    assert_equal nil, response
  end

  def test_agent_command_results
    @http_handle.respond_to(:agent_command_results, {})
    response = @service.agent_command_results({'1' => {}})
    assert_equal({}, response)
  end

  def test_request_timeout
    with_config(:timeout => 600) do
      service = NewRelic::Agent::NewRelicService.new('abcdef', @server)
      assert_equal 600, service.request_timeout
    end
  end

  def test_should_throw_received_errors
    assert_raises NewRelic::Agent::ServerConnectionException do
      @service.send(:invoke_remote, :bogus_method)
    end
  end

  def test_should_connect_to_proxy_only_once_per_run
    @service.expects(:get_redirect_host).once

    @service.connect
    @http_handle.respond_to(:metric_data, 0)
    stats_hash = NewRelic::Agent::StatsHash.new
    stats_hash.harvested_at = Time.now
    @service.metric_data(stats_hash)

    @http_handle.respond_to(:transaction_sample_data, 1)
    @service.transaction_sample_data([])

    @http_handle.respond_to(:sql_trace_data, 2)
    @service.sql_trace_data([])
  end

  # for PRUBY proxy compatibility
  def test_should_raise_exception_on_401
    @http_handle.reset
    @http_handle.respond_to(:get_redirect_host, 'bad license', :code => 401)
    assert_raises NewRelic::Agent::LicenseException do
      @service.get_redirect_host
    end
  end

  # protocol 9
  def test_should_raise_exception_on_413
    @http_handle.respond_to(:metric_data, 'too big', :code => 413)
    assert_raises NewRelic::Agent::UnrecoverableServerException do
      stats_hash = NewRelic::Agent::StatsHash.new
      @service.metric_data(stats_hash)
    end
  end

  # protocol 9
  def test_should_raise_exception_on_415
    @http_handle.respond_to(:metric_data, 'too big', :code => 415)
    assert_raises NewRelic::Agent::UnrecoverableServerException do
      stats_hash = NewRelic::Agent::StatsHash.new
      @service.metric_data(stats_hash)
    end
  end

  if NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported?
    def test_json_marshaller_handles_responses_from_collector
      marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
      assert_equal ['beep', 'boop'], marshaller.load('{"return_value": ["beep","boop"]}')
    end

    def test_json_marshaller_handles_errors_from_collector
      marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
      assert_raises(NewRelic::Agent::NewRelicService::CollectorError,
                   'JavaCrash: error message') do
        marshaller.load('{"exception": {"message": "error message", "error_type": "JavaCrash"}}')
      end
    end

    def test_json_marshaller_logs_on_empty_response_from_collector
      marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
      expects_logging(:error, any_parameters)
      assert_nil marshaller.load('')
    end

    def test_json_marshaller_logs_on_nil_response_from_collector
      marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
      expects_logging(:error, any_parameters)
      assert_nil marshaller.load(nil)
    end

    def test_raises_serialization_error_if_json_serialization_fails
      ::NewRelic::JSONWrapper.stubs(:dump).raises(RuntimeError.new('blah'))
      assert_raises(NewRelic::Agent::SerializationError) do
        @service.send(:invoke_remote, 'wiggle', [{}])
      end
    end

    def test_raises_serialization_error_if_encoding_normalization_fails
      with_config(:normalize_json_string_encodings => true) do
        @http_handle.respond_to(:wiggle, 'hi')
        NewRelic::JSONWrapper.stubs(:normalize).raises('blah')
        assert_raises(NewRelic::Agent::SerializationError) do
          @service.send(:invoke_remote, 'wiggle', [{}])
        end
      end
    end

    def test_skips_normalization_if_configured_to
      @http_handle.respond_to(:wiggle, 'hello')
      with_config(:normalize_json_string_encodings => false) do
        NewRelic::JSONWrapper.expects(:normalize).never
        @service.send(:invoke_remote, 'wiggle', [{ 'foo' => 'bar' }])
      end
    end

    def test_json_marshaller_handles_binary_strings
      input_string = (0..255).to_a.pack("C*")
      roundtripped_string = roundtrip_data(input_string)

      if NewRelic::LanguageSupport.supports_string_encodings?
        assert_equal(Encoding.find('ASCII-8BIT'), input_string.encoding)
      end

      expected = force_to_utf8(input_string.dup)
      assert_equal(expected, roundtripped_string)
    end

    if NewRelic::LanguageSupport.supports_string_encodings?
      def test_json_marshaller_handles_strings_with_incorrect_encoding
        input_string = (0..255).to_a.pack("C*").force_encoding("UTF-8")
        roundtripped_string = roundtrip_data(input_string)

        assert_equal(Encoding.find('UTF-8'), input_string.encoding)
        expected = input_string.dup.force_encoding('ISO-8859-1').encode('UTF-8')
        assert_equal(expected, roundtripped_string)
      end
    end

    def test_json_marshaller_failure_when_not_normalizing
      input_string = (0..255).to_a.pack("C*")
      assert_raises(NewRelic::Agent::SerializationError) do
        roundtrip_data(input_string, false)
      end
    end

    def test_json_marshaller_should_handle_crazy_strings
      root = generate_object_graph_with_crazy_strings
      result = roundtrip_data(root)

      # Note that there's technically a possibility of collision here:
      # if two of the randomly-generated key strings happen to normalize to the
      # same value, we might see <100 results, but the chances of this seem
      # vanishingly small.
      assert_equal(100, result.length)
    end

    def test_normalization_should_account_for_to_collector_array
      binary_string = generate_random_byte_sequence
      data = DummyDataClass.new(binary_string, [])
      result = roundtrip_data(data)

      expected_string = force_to_utf8(binary_string)
      assert_equal(expected_string, result[0])
    end

    def test_normalization_should_account_for_to_collector_array_with_nested_encodings
      binary_string = generate_random_byte_sequence
      data = DummyDataClass.new(binary_string, [binary_string])
      result = roundtrip_data(data)

      expected_string = force_to_utf8(binary_string)
      assert_equal(expected_string, result[0])

      base64_encoded_compressed_json_field = result[1]
      compressed_json_field = Base64.decode64(base64_encoded_compressed_json_field)
      json_field = Zlib::Inflate.inflate(compressed_json_field)
      field = JSON.parse(json_field)

      assert_equal([expected_string], field)
    end
  end

  def test_compress_request_if_needed_compresses_large_payloads
    large_payload = 'a' * 65 * 1024
    body, encoding = @service.compress_request_if_needed(large_payload)
    assert_equal(large_payload, Zlib::Inflate.inflate(body))
    assert_equal('deflate', encoding)
  end

  def test_compress_request_if_needed_passes_thru_small_payloads
    payload = 'a' * 100
    body, encoding = @service.compress_request_if_needed(payload)
    assert_equal(payload, body)
    assert_equal('identity', encoding)
  end

  def test_marshaller_obeys_requested_encoder
    dummy = ['hello there']
    def dummy.to_collector_array(encoder)
      self.map { |x| encoder.encode(x) }
    end
    marshaller = NewRelic::Agent::NewRelicService::Marshaller.new

    identity_encoder = NewRelic::Agent::NewRelicService::Encoders::Identity

    prepared = marshaller.prepare(dummy, :encoder => identity_encoder)
    assert_equal(dummy, prepared)

    prepared = marshaller.prepare(dummy, :encoder => ReverseEncoder)
    decoded = prepared.map { |x| x.reverse }
    assert_equal(dummy, decoded)
  end

  def test_marshaller_prepare_passes_on_options
    inner_array = ['abcd']
    def inner_array.to_collector_array(encoder)
      self.map { |x| encoder.encode(x) }
    end
    dummy = [[inner_array]]
    marshaller = NewRelic::Agent::NewRelicService::Marshaller.new
    prepared = marshaller.prepare(dummy, :encoder => ReverseEncoder)
    assert_equal([[['dcba']]], prepared)
  end

  def test_marshaller_handles_force_restart_exception
    error_data = {
      'error_type' => 'NewRelic::Agent::ForceRestartException',
      'message'    => 'test'
    }
    error = @service.marshaller.parsed_error(error_data)
    assert_equal NewRelic::Agent::ForceRestartException, error.class
    assert_equal 'test', error.message
  end

  def test_marshaller_handles_force_disconnect_exception
    error_data = {
      'error_type' => 'NewRelic::Agent::ForceDisconnectException',
      'message'    => 'test'
    }
    error = @service.marshaller.parsed_error(error_data)
    assert_equal NewRelic::Agent::ForceDisconnectException, error.class
    assert_equal 'test', error.message
  end

  def test_marshaller_handles_license_exception
    error_data = {
      'error_type' => 'NewRelic::Agent::LicenseException',
      'message'    => 'test'
    }
    error = @service.marshaller.parsed_error(error_data)
    assert_equal NewRelic::Agent::LicenseException, error.class
    assert_equal 'test', error.message
  end

  def test_marshaller_handles_unknown_errors
    error = @service.marshaller.parsed_error('error_type' => 'OogBooga',
                                             'message' => 'test')
    assert_equal NewRelic::Agent::NewRelicService::CollectorError, error.class
    assert_equal 'OogBooga: test', error.message
  end

  def test_build_metric_data_array
    hash = NewRelic::Agent::StatsHash.new

    spec1 = NewRelic::MetricSpec.new('foo')
    spec2 = NewRelic::MetricSpec.new('bar')
    hash.record(spec1, 1)
    hash.record(spec2, 2)

    metric_data_array = @service.build_metric_data_array(hash)

    assert_equal(2, metric_data_array.size)
    metric_data_1 = metric_data_array.find { |md| md.metric_spec == spec1 }
    metric_data_2 = metric_data_array.find { |md| md.metric_spec == spec2 }
    assert_equal(hash[spec1], metric_data_1.stats)
    assert_equal(hash[spec2], metric_data_2.stats)
  end

  def test_build_metric_data_array_omits_empty_stats
    hash = NewRelic::Agent::StatsHash.new

    spec1 = NewRelic::MetricSpec.new('foo')
    spec2 = NewRelic::MetricSpec.new('bar')
    hash.record(spec1, 1)
    hash.record(spec2) { |s| s.call_count = 0 }

    metric_data_array = @service.build_metric_data_array(hash)
    assert_equal(1, metric_data_array.size)

    metric_data = metric_data_array.first
    assert_equal(spec1, metric_data.metric_spec)
  end

  def test_valid_to_marshal
    assert @service.valid_to_marshal?({})
  end

  def test_not_valid_to_marshal
    @service.marshaller.stubs(:dump).raises(StandardError.new("Failed to marshal"))
    refute @service.valid_to_marshal?({})
  end

  def test_not_valid_to_marshal_with_system_stack_error
    @service.marshaller.stubs(:dump).raises(SystemStackError.new)
    refute @service.valid_to_marshal?({})
  end

  def test_supportability_metrics_with_item_count
    NewRelic::Agent.drop_buffered_data

    payload = ['eggs', 'spam']
    @http_handle.respond_to(:foobar, 'foobar')
    @service.send(:invoke_remote, :foobar, payload, :item_count => 12)

    expected_size_bytes = @service.marshaller.dump(payload).size
    expected_values = {
      :call_count           => 1,
      :total_call_time      => expected_size_bytes,
      :total_exclusive_time => 12
    }

    assert_metrics_recorded(
      'Supportability/invoke_remote'                  => { :call_count => 1 },
      'Supportability/invoke_remote/foobar'           => { :call_count => 1 },
      'Supportability/invoke_remote_serialize'        => { :call_count => 1 },
      'Supportability/invoke_remote_serialize/foobar' => { :call_count => 1},
      'Supportability/invoke_remote_size'             => expected_values,
      'Supportability/invoke_remote_size/foobar'      => expected_values
    )
  end

  def test_supportability_metrics_without_item_count
    NewRelic::Agent.drop_buffered_data

    payload = ['eggs', 'spam']
    @http_handle.respond_to(:foobar, 'foobar')
    @service.send(:invoke_remote, :foobar, payload)

    expected_size_bytes = @service.marshaller.dump(payload).size
    expected_values = {
      :call_count           => 1,
      :total_call_time      => expected_size_bytes,
      :total_exclusive_time => 0
    }

    assert_metrics_recorded(
      'Supportability/invoke_remote'                  => { :call_count => 1 },
      'Supportability/invoke_remote/foobar'           => { :call_count => 1 },
      'Supportability/invoke_remote_serialize'        => { :call_count => 1 },
      'Supportability/invoke_remote_serialize/foobar' => { :call_count => 1},
      'Supportability/invoke_remote_size'             => expected_values,
      'Supportability/invoke_remote_size/foobar'      => expected_values
    )
  end

  def test_supportability_metrics_with_serialization_failure
    NewRelic::Agent.drop_buffered_data

    payload = ['eggs', 'spam']
    @http_handle.respond_to(:foobar, 'foobar')
    @service.marshaller.stubs(:dump).raises(StandardError.new)

    assert_raises(NewRelic::Agent::SerializationError) do
      @service.send(:invoke_remote, :foobar, payload)
    end

    expected_values = { :call_count => 1 }

    assert_metrics_recorded(
      'Supportability/invoke_remote'                => expected_values,
      'Supportability/invoke_remote/foobar'         => expected_values,
      'Supportability/serialization_failure'        => expected_values,
      'Supportability/serialization_failure/foobar' => expected_values
    )

    assert_metrics_not_recorded([
      'Supportability/invoke_remote_serialize',
      'Supportability/invoke_remote_serialize/foobar',
      'Supportability/invoke_remote_size',
      'Supportability/invoke_remote_size/foobar'
    ])
  end

  def test_force_restart_closes_shared_connections
    @service.establish_shared_connection
    @service.force_restart
    refute @service.has_shared_connection?
  end

  def test_marshal_with_json_only
    with_config(:marshaller => 'pruby') do
      assert_equal 'json', @service.marshaller.format
    end
  end

  def build_stats_hash(items={})
    hash = NewRelic::Agent::StatsHash.new
    items.each do |key, value|
      hash.record(NewRelic::MetricSpec.new(key), value)
    end
    hash.harvested_at = Time.now
    hash
  end

  def force_to_utf8(string)
    if NewRelic::LanguageSupport.supports_string_encodings?
      string.force_encoding('ISO-8859-1').encode('UTF-8')
    else
      Iconv.iconv('utf-8', 'iso-8859-1', string).join
    end
  end

  def generate_random_byte_sequence(length=255, encoding=nil)
    bytes = []
    alphabet = (0..255).to_a
    meth = alphabet.respond_to?(:sample) ? :sample : :choice
    length.times { bytes << alphabet.send(meth) }

    string = bytes.pack("C*")
    string.force_encoding(encoding) if encoding
    string
  end

  def generate_object_graph_with_crazy_strings
    strings = {}
    100.times do
      key_string = generate_random_byte_sequence(255, random_encoding)
      value_string = generate_random_byte_sequence(255, random_encoding)
      strings[key_string] = value_string
    end
    strings
  end

  def random_encoding
    if NewRelic::LanguageSupport.supports_string_encodings?
      Encoding.list.sample
    else
      nil
    end
  end

  def roundtrip_data(data, normalize = true)
    with_config(:normalize_json_string_encodings => normalize) do
      @http_handle.respond_to(:roundtrip, 'roundtrip')
      @service.send(:invoke_remote, 'roundtrip', [data])
      @http_handle.last_request_payload[0]
    end
  end

  class DummyDataClass
    def initialize(string, object_graph)
      @string = string
      @object_graph = object_graph
    end

    def to_collector_array(encoder)
      [
        @string,
        encoder.encode(@object_graph)
      ]
    end
  end

  module ReverseEncoder
    def self.encode(data)
      data.reverse
    end
  end

  # This class acts as a stand-in for instances of Net::HTTP, which represent
  # HTTP connections.
  #
  # It can record the start / finish / request calls made to it, and exposes
  # that call sequence via the #calls accessor.
  #
  # It can also be configured to generate dummy responses for calls to request,
  # via the #respond_to method.
  class HTTPHandle
    # This module gets included into the Net::HTTPResponse subclasses that we
    # create below. We do this because the code in NewRelicService switches
    # behavior based on the type of response that is returned, and we want to be
    # able to create dummy responses for testing easily.
    module HTTPResponseMock
      attr_accessor :code, :body, :message, :headers

      def initialize(body, code=200, message='OK')
        @code = code
        @body = body
        @message = message
        @headers = {}
      end

      def [](key)
        @headers[key]
      end
    end

    HTTPSuccess               = Class.new(Net::HTTPSuccess)               { include HTTPResponseMock }
    HTTPUnauthorized          = Class.new(Net::HTTPUnauthorized)          { include HTTPResponseMock }
    HTTPNotFound              = Class.new(Net::HTTPNotFound)              { include HTTPResponseMock }
    HTTPRequestEntityTooLarge = Class.new(Net::HTTPRequestEntityTooLarge) { include HTTPResponseMock }
    HTTPUnsupportedMediaType  = Class.new(Net::HTTPUnsupportedMediaType)  { include HTTPResponseMock }

    attr_accessor :read_timeout
    attr_reader :calls, :last_request

    def initialize(name)
      @name    = name
      @started = false
      reset
    end

    def start
      @calls << :start
      @started = true
    end

    def finish
      @calls << :finish
      @started = false
    end

    def inspect
      "<HTTPHandle: #{@name}>"
    end

    def started?
      @started
    end

    def address
      'whereever.com'
    end

    def port
      8080
    end

    def create_response_mock(payload, opts={})
      opts = {
        :code => 200,
        :format => :json
      }.merge(opts)

      if opts[:code] == 401
        klass = HTTPUnauthorized
      elsif opts[:code] == 413
        klass = HTTPRequestEntityTooLarge
      elsif opts[:code] == 415
        klass = HTTPUnsupportedMediaType
      elsif opts[:code] >= 400
        klass = HTTPServerError
      else
        klass = HTTPSuccess
      end

      klass.new(JSON.dump('return_value' => payload), opts[:code], {})
    end

    def respond_to(method, payload, opts={})
      case payload
      when Exception then rsp = payload
      else                rsp = create_response_mock(payload, opts)
      end

      @route_table[method.to_s] = rsp
    end

    def request(*args)
      @calls << :request

      request = args.first
      @last_request = request

      route = @route_table.keys.find { |r| request.path.include?(r) }

      if route
        response = @route_table[route]
        raise response if response.kind_of?(Exception)
        response
      else
        HTTPNotFound.new('not found', 404)
      end
    end

    def reset
      @calls = []
      @route_table = {}
      @last_request = nil
    end

    def last_request_payload
      return nil unless @last_request && @last_request.body

      body = @last_request.body
      content_encoding = @last_request['Content-Encoding']
      body = Zlib::Inflate.inflate(body) if content_encoding == 'deflate'

      uri = URI.parse(@last_request.path)
      params = CGI.parse(uri.query)
      format = params['marshal_format'].first
      if format == 'json'
        JSON.load(body)
      else
        Marshal.load(body)
      end
    end
  end
end
