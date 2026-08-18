# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require 'new_relic/agent/commands/thread_profiler_session'

class NewRelicServiceTest < Minitest::Test
  def setup
    @server = NewRelic::Control::Server.new('somewhere.example.com', 30303)
    @service = NewRelic::Agent::NewRelicService.new('license-key', @server)

    @http_handle = create_http_handle
    @http_handle.respond_to(:preconnect, preconnect_response('localhost'))
    connect_response = {
      'config' => 'some config directives',
      'agent_run_id' => 1
    }
    @http_handle.respond_to(:connect, connect_response)

    @service.stubs(:create_http_connection).returns(@http_handle)
  end

  def teardown
    NewRelic::Agent.config.reset_to_defaults
    reset_buffers_and_caches
  end

  def create_http_handle(name = 'connection')
    HTTPHandle.new(name)
  end

  def test_session_handles_timeouts_opening_connection_gracefully
    @http_handle.stubs(:start).raises(Net::OpenTimeout)

    block_ran = false

    assert_raises(::NewRelic::Agent::ServerConnectionException) do
      @service.session do
        block_ran = true
      end
    end

    refute block_ran, 'Expected block passed to #session to have not run'
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
        assert_same(@service.http_connection, handle1)
        assert_same(@service.http_connection, handle1)
      end
    end

    assert(block_ran)

    assert_equal([:start, :finish], handle1.calls)
    assert_empty(handle2.calls)
  end

  def test_multiple_http_handles_are_used_outside_session_block
    handle1 = create_http_handle
    handle2 = create_http_handle
    @service.stubs(:create_http_connection).returns(handle1, handle2)

    assert_same(@service.http_connection, handle1)
    assert_same(@service.http_connection, handle2)
  end

  # Calling start on a Net::HTTP instance results in connection keep-alive
  # being used, which means that the connection won't be automatically closed
  # once a request is issued. For calls to the service outside of a session
  # block (/preconnect and /connect, namely), we actually want the
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
    assert_empty(conn2.calls)
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
    assert_empty(conn2.calls)
  end

  def test_no_default_cert_file_path
    refute @service.cert_file_path
  end

  def test_cert_file_path_uses_path_from_config
    fake_cert_path = '/certpath/cert.pem'

    with_config(:ca_bundle_path => fake_cert_path) do
      assert_equal @service.cert_file_path, fake_cert_path
    end
  end

  def test_initialize_uses_license_key_from_config
    with_config(:license_key => 'abcde') do
      service = NewRelic::Agent::NewRelicService.new

      assert_equal 'abcde', service.send(:license_key)
    end
  end

  def test_initialize_uses_license_key_from_manual_start
    service = NewRelic::Agent::NewRelicService.new
    NewRelic::Agent.manual_start(:license_key => 'geronimo')

    assert_equal 'geronimo', service.send(:license_key)
    NewRelic::Agent.shutdown
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

  def test_connect_uses_proxy_collector_if_preconnect_returns_no_redirect_host
    @http_handle.reset
    @http_handle.respond_to(:preconnect, preconnect_response(nil))
    @http_handle.respond_to(:connect, 'agent_run_id' => 1)

    @service.connect

    assert_equal 'somewhere.example.com', @service.collector.name
  end

  def test_connect_sets_agent_id
    @http_handle.reset
    @http_handle.respond_to(:preconnect, preconnect_response('localhost'))
    @http_handle.respond_to(:connect, 'agent_run_id' => 666)

    @service.connect

    assert_equal 666, @service.agent_id
  end

  def test_preconnect_never_uses_redirect_host
    # Use locally configured collector for initial preconnect
    initial_preconnect_log = with_array_logger(level = :debug) { @service.preconnect }

    assert_log_contains initial_preconnect_log, 'Sending request to somewhere.example.com'

    # Connect has set the redirect host as the collector
    initial_connect_log = with_array_logger(level = :debug) { @service.connect }

    assert_log_contains initial_connect_log, 'Sending request to localhost'
    assert_log_contains initial_connect_log, Regexp.escape('license_key=license-ke*')

    # If we need to reconnect, preconnect should use the locally configured collector again
    reconnect_log = with_array_logger(level = :debug) { @service.preconnect }

    assert_log_contains reconnect_log, 'Sending request to somewhere.example.com'
    assert_log_contains reconnect_log, Regexp.escape('license_key=license-ke*')
  end

  def test_high_security_mode_sent_on_preconnect
    with_config(:high_security => true) do
      @service.preconnect
      payload = @http_handle.last_request_payload.first

      assert payload['high_security']
    end

    with_config(:high_security => false) do
      @service.preconnect
      payload = @http_handle.last_request_payload.first

      refute_nil payload['high_security']
      refute payload['high_security']
    end
  end

  def test_shutdown
    @service.agent_id = 666
    @http_handle.respond_to(:shutdown, 'shut this bird down')
    response = @service.shutdown(Process.clock_gettime(Process::CLOCK_REALTIME))

    assert_equal 'shut this bird down', response
  end

  def test_should_not_shutdown_if_never_connected
    @http_handle.respond_to(:shutdown, 'shut this bird down')
    response = @service.shutdown(Process.clock_gettime(Process::CLOCK_REALTIME))

    assert_nil response
  end

  def test_metric_data
    dummy_rsp = 'met rick date uhh'
    @http_handle.respond_to(:metric_data, dummy_rsp)
    stats_hash = NewRelic::Agent::StatsHash.new
    stats_hash.harvested_at = Process.clock_gettime(Process::CLOCK_REALTIME)
    response = @service.metric_data(stats_hash)

    assert_equal 4, @http_handle.last_request_payload.size
    assert_equal dummy_rsp, response
  end

  def test_metric_data_sends_harvest_timestamps
    @http_handle.respond_to(:metric_data, 'foo')

    t0 = nr_freeze_process_time
    stats_hash = NewRelic::Agent::StatsHash.new
    stats_hash.harvested_at = Process.clock_gettime(Process::CLOCK_REALTIME)

    @service.metric_data(stats_hash)
    payload = @http_handle.last_request_payload
    _, last_harvest_timestamp, harvest_timestamp, _ = payload

    assert_in_delta(t0, harvest_timestamp, 0.0001)

    t1 = advance_process_time(10)
    stats_hash.harvested_at = t1

    @service.metric_data(stats_hash)
    payload = @http_handle.last_request_payload
    _, last_harvest_timestamp, harvest_timestamp, _ = payload

    assert_in_delta(t1, harvest_timestamp, 0.0001)
    assert_in_delta(t0, last_harvest_timestamp, 0.0001)
  end

  def test_metric_data_harvest_time_based_on_stats_hash_creation
    t0 = nr_freeze_process_time
    dummy_rsp = 'met rick date uhh'
    @http_handle.respond_to(:metric_data, dummy_rsp)

    advance_process_time(10)
    stats_hash = NewRelic::Agent::StatsHash.new
    advance_process_time(1)
    stats_hash.harvested_at = Process.clock_gettime(Process::CLOCK_REALTIME)

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

  def test_error_event_data
    @http_handle.respond_to(:error_event_data, 'some error events')
    response = @service.error_event_data([{}, []])

    assert_equal 'some error events', response
  end

  def test_span_event_data
    @http_handle.respond_to(:span_event_data, 'some span events')
    response = @service.span_event_data([{}, []])

    assert_equal 'some span events', response
  end

  def test_log_event_data
    @http_handle.respond_to(:log_event_data, 'some log events')
    response = @service.log_event_data([{}, []])

    assert_equal 'some log events', response
  end

  # Although thread profiling is only available in some circumstances, the
  # service communication doesn't care about that at all
  def test_profile_data
    @http_handle.respond_to(:profile_data, 'profile' => 123)
    response = @service.profile_data([])

    assert_equal({'profile' => 123}, response)
  end

  def test_profile_data_does_not_normalize_encodings
    @http_handle.respond_to(:profile_data, nil)
    NewRelic::Agent::EncodingNormalizer.expects(:normalize_object).never
    @service.profile_data([])
  end

  # profiles_data doesn't use invoke_raw_method like every other method here -- OTLP/HTTP
  # directly to /v1/profiles, api-key header, no gzip.
  def test_profiles_data_posts_to_the_v1_profiles_path
    @http_handle.respond_to('v1/profiles', '', :code => 202)

    @service.profiles_data('raw-profile-bytes')

    assert_equal '/v1/profiles', @http_handle.last_request.path
  end

  def test_profiles_data_sends_the_license_key_as_the_api_key_header
    @http_handle.respond_to('v1/profiles', '', :code => 202)

    @service.profiles_data('raw-profile-bytes')

    assert_equal 'license-key', @http_handle.last_request['api-key']
  end

  def test_profiles_data_sends_the_raw_bytes_uncompressed_without_json_marshalling
    large_payload = 'x' * (NewRelic::Agent::NewRelicService::MIN_BYTE_SIZE_TO_COMPRESS + 1000)
    @http_handle.respond_to('v1/profiles', '', :code => 202)

    @service.profiles_data(large_payload)

    assert_equal large_payload, @http_handle.last_request.body
    assert_nil @http_handle.last_request['Content-Encoding']
  end

  def test_profiles_data_sets_the_protobuf_content_type
    @http_handle.respond_to('v1/profiles', '', :code => 202)

    @service.profiles_data('raw-profile-bytes')

    assert_equal 'application/x-protobuf', @http_handle.last_request.content_type
  end

  def test_profiles_data_handles_a_202_accepted_response_without_raising
    @http_handle.respond_to('v1/profiles', '', :code => 202)

    response = @service.profiles_data('raw-profile-bytes')

    assert_equal 202, response.code
  end

  def test_profiles_data_records_a_failure_metric_and_returns_nil_on_a_server_error_response
    @http_handle.respond_to('v1/profiles', '', :code => 500)

    response = @service.profiles_data('raw-profile-bytes')

    assert_nil response
    assert_metrics_recorded('Supportability/Ruby/Profiling/Export/Failure')
  end

  def test_profiles_data_records_a_failure_metric_and_returns_nil_on_a_client_error_response
    @http_handle.respond_to('v1/profiles', '', :code => 400)

    response = @service.profiles_data('raw-profile-bytes')

    assert_nil response
    assert_metrics_recorded('Supportability/Ruby/Profiling/Export/Failure')
  end

  def test_profiles_data_with_nil_bytes_does_not_raise
    assert_nil @service.profiles_data(nil)
    assert_metrics_recorded('Supportability/Ruby/Profiling/Export/Failure')
  end

  def test_profiles_data_records_size_and_duration_supportability_metrics
    @http_handle.respond_to('v1/profiles', '', :code => 202)

    @service.profiles_data('raw-profile-bytes')

    assert_metrics_recorded([
      'Supportability/Ruby/OTLP/Profiles/Output/Bytes',
      'Supportability/Ruby/Profiling/Export/Duration'
    ])
  end

  def test_profiles_data_rescues_connection_failures_and_records_a_failure_metric
    @service.stubs(:create_http_connection).raises(Errno::ECONNREFUSED)

    response = @service.profiles_data('raw-profile-bytes')

    assert_nil response
    assert_metrics_recorded('Supportability/Ruby/Profiling/Export/Failure')
  end

  def test_profiles_data_reuses_the_connection_across_calls
    @http_handle.respond_to('v1/profiles', '', :code => 202)

    @service.profiles_data('raw-profile-bytes')
    @service.profiles_data('raw-profile-bytes')

    assert_equal [:start, :request, :request], @http_handle.calls
  end

  def test_profiles_data_reconnects_after_a_failed_request
    ordering = sequence('profiles_requests')
    @http_handle.expects(:request).raises(Errno::ECONNRESET).in_sequence(ordering)
    @http_handle.expects(:request).returns(@http_handle.create_response_mock('', :code => 202)).in_sequence(ordering)

    first_response = @service.profiles_data('raw-profile-bytes')
    second_response = @service.profiles_data('raw-profile-bytes')

    assert_nil first_response
    refute_nil second_response
    assert_equal 2, @http_handle.calls.count(:start)
  end

  def test_build_profiles_request_skips_audit_logging_when_disabled
    with_config(:'audit_log.enabled' => false) do
      @http_handle.respond_to('v1/profiles', '', :code => 202)
      audit_logger = @service.instance_variable_get(:@audit_logger)
      audit_logger.expects(:log_request_headers).never
      audit_logger.expects(:log_profiles_request).never

      @service.profiles_data('raw-profile-bytes')
    end
  end

  def test_build_profiles_request_audits_headers_with_the_api_key_redacted
    with_config(:'audit_log.enabled' => true) do
      @http_handle.respond_to('v1/profiles', '', :code => 202)
      audit_logger = @service.instance_variable_get(:@audit_logger)
      audit_logger.expects(:log_request_headers).with do |uri, headers|
        uri == "#{@server}/v1/profiles" && headers['api-key'] == 'license-ke*'
      end
      audit_logger.stubs(:log_profiles_request)

      @service.profiles_data('raw-profile-bytes')
    end
  end

  def test_build_profiles_request_audits_the_body
    with_config(:'audit_log.enabled' => true) do
      @http_handle.respond_to('v1/profiles', '', :code => 202)
      audit_logger = @service.instance_variable_get(:@audit_logger)
      audit_logger.stubs(:log_request_headers)
      audit_logger.expects(:log_profiles_request).with("#{@server}/v1/profiles", 'raw-profile-bytes'.inspect)

      @service.profiles_data('raw-profile-bytes')
    end
  end

  def test_build_profiles_request_does_not_leak_the_raw_license_key_to_the_audit_log
    with_config(:'audit_log.enabled' => true) do
      @http_handle.respond_to('v1/profiles', '', :code => 202)
      audit_logger = @service.instance_variable_get(:@audit_logger)
      audit_logger.expects(:log_request_headers).with do |_uri, headers|
        refute_includes headers.values, 'license-key'
        true
      end
      audit_logger.stubs(:log_profiles_request)

      @service.profiles_data('raw-profile-bytes')
    end
  end

  def test_build_profiles_request_does_not_mutate_the_real_request_headers
    with_config(:'audit_log.enabled' => true) do
      @http_handle.respond_to('v1/profiles', '', :code => 202)

      @service.profiles_data('raw-profile-bytes')

      assert_equal 'license-key', @http_handle.last_request['api-key']
    end
  end

  def test_profiles_audit_body_decodes_via_profile_encoder_when_defined
    refute defined?(NewRelic::Agent::ContinuousProfiling::ProfileEncoder), 'test assumes ProfileEncoder is not already loaded in the unit suite'
    fake_encoder = Class.new do
      def self.decode_for_audit(bytes)
        "decoded: #{bytes}"
      end
    end
    NewRelic::Agent::ContinuousProfiling.const_set(:ProfileEncoder, fake_encoder)

    assert_equal 'decoded: raw-profile-bytes', @service.send(:profiles_audit_body, 'raw-profile-bytes')
  ensure
    NewRelic::Agent::ContinuousProfiling.send(:remove_const, :ProfileEncoder)
  end

  def test_profiles_audit_body_falls_back_to_inspect_when_profile_encoder_is_undefined
    refute defined?(NewRelic::Agent::ContinuousProfiling::ProfileEncoder), 'test assumes ProfileEncoder is not loaded in the unit suite'

    assert_equal 'raw-profile-bytes'.inspect, @service.send(:profiles_audit_body, 'raw-profile-bytes')
  end

  def test_get_agent_commands
    @service.agent_id = 666
    @http_handle.respond_to(:get_agent_commands, [1, 2, 3])

    response = @service.get_agent_commands

    assert_equal [1, 2, 3], response
  end

  def test_get_agent_commands_with_no_response
    @service.agent_id = 666
    @http_handle.respond_to(:get_agent_commands, nil)

    response = @service.get_agent_commands

    assert_nil response
  end

  def test_agent_command_results
    @http_handle.respond_to(:agent_command_results, {})
    response = @service.agent_command_results({'1' => {}})

    assert_empty(response)
  end

  def test_request_timeout
    with_config(:timeout => 600) do
      service = NewRelic::Agent::NewRelicService.new('abcdef', @server)

      assert_equal 600, service.request_timeout
    end
  end

  def test_should_throw_received_errors
    assert_raises NewRelic::Agent::UnrecoverableServerException do
      @service.send(:invoke_remote, :bogus_method)
    end
  end

  def test_should_connect_to_proxy_only_once_per_run
    @service.expects(:preconnect).once

    @service.connect
    @http_handle.respond_to(:metric_data, 0)
    stats_hash = NewRelic::Agent::StatsHash.new
    stats_hash.harvested_at = Process.clock_gettime(Process::CLOCK_REALTIME)
    @service.metric_data(stats_hash)

    @http_handle.respond_to(:transaction_sample_data, 1)
    @service.transaction_sample_data([])

    @http_handle.respond_to(:sql_trace_data, 2)
    @service.sql_trace_data([])
  end

  def self.check_status_code_handling(expected_exceptions)
    expected_exceptions.each do |status_code, exception_type|
      method_name = "test_#{status_code}_raises_#{exception_type.name.split('::').last}"
      define_method(method_name) do
        @http_handle.respond_to(:metric_data, 'payload', :code => status_code)

        stats_hash = NewRelic::Agent::StatsHash.new

        assert_raises exception_type do
          @service.metric_data(stats_hash)
        end
      end
    end
  end

  check_status_code_handling(400 => NewRelic::Agent::UnrecoverableServerException,
    401 => NewRelic::Agent::ForceRestartException,
    403 => NewRelic::Agent::UnrecoverableServerException,
    405 => NewRelic::Agent::UnrecoverableServerException,
    407 => NewRelic::Agent::UnrecoverableServerException,
    408 => NewRelic::Agent::ServerConnectionException,
    409 => NewRelic::Agent::ForceRestartException,
    410 => NewRelic::Agent::ForceDisconnectException,
    411 => NewRelic::Agent::UnrecoverableServerException,
    413 => NewRelic::Agent::UnrecoverableServerException,
    415 => NewRelic::Agent::UnrecoverableServerException,
    417 => NewRelic::Agent::UnrecoverableServerException,
    429 => NewRelic::Agent::ServerConnectionException,
    431 => NewRelic::Agent::UnrecoverableServerException)

  def self.check_agent_health_status_updates(expected_exceptions)
    expected_exceptions.each do |status_code|
      method_name = "test_#{status_code}_updates_agent_health_check"
      define_method(method_name) do
        NewRelic::Agent.agent.health_check.instance_variable_set(:@continue, true)
        NewRelic::Agent.agent.health_check.instance_variable_set(:@status, NewRelic::Agent::HealthCheck::HEALTHY)

        begin
          @http_handle.respond_to(:metric_data, 'payload', :code => status_code)
          stats_hash = NewRelic::Agent::StatsHash.new
          @service.metric_data(stats_hash)
        rescue
          # no-op, raise the error
        end

        expected = {
          healthy: false,
          last_error: 'NR-APM-004',
          message: "HTTP error response code [#{status_code}] recevied from New Relic while sending data type [metric_data]"
        }

        assert_equal expected, NewRelic::Agent.agent.health_check.instance_variable_get(:@status)
      end
    end
  end

  # Some status codes may also eventually report other health checks
  # * 401 is INVALID_LICENSE_KEY and overwrites HTTP_ERROR in handle_error_response
  # * 410 is FORCED_DISCONNECT and overwrites HTTP_ERROR later when ForceDisconnectException is rescued in handle_force_disconnect
  # However in this method, codes should report HTTP_ERROR
  check_agent_health_status_updates([
    400, 403, 405, 407, 408, 409, 410, 411, 413, 415, 417, 429, 431
  ])

  def test_401_updates_invalid_license_key_health_check
    NewRelic::Agent.agent.health_check.instance_variable_set(:@continue, true)
    NewRelic::Agent.agent.health_check.instance_variable_set(:@status, NewRelic::Agent::HealthCheck::HEALTHY)

    begin
      @http_handle.respond_to(:metric_data, 'payload', :code => 401)
      stats_hash = NewRelic::Agent::StatsHash.new
      @service.metric_data(stats_hash)
    rescue
      # no-op, raise the error
    end

    assert_equal NewRelic::Agent::HealthCheck::INVALID_LICENSE_KEY,
      NewRelic::Agent.agent.health_check.instance_variable_get(:@status)
  end

  def test_401_logs_invalid_license_key_error
    @http_handle.respond_to(:metric_data, 'payload', :code => 401)

    logger = with_array_logger(level = :error) do
      stats_hash = NewRelic::Agent::StatsHash.new

      assert_raises NewRelic::Agent::ForceRestartException do
        @service.metric_data(stats_hash)
      end
    end

    assert_log_contains logger, 'Invalid license key: license-ke*'
  end

  # protocol 17
  def test_supportability_metrics_for_http_error_responses
    NewRelic::Agent.drop_buffered_data
    @http_handle.respond_to(:metric_data, 'bad format', :code => 400)
    stats_hash = NewRelic::Agent::StatsHash.new

    assert_raises NewRelic::Agent::UnrecoverableServerException do
      @service.metric_data(stats_hash)
    end

    assert_metrics_recorded(
      'Supportability/Agent/Collector/HTTPError/400' => {:call_count => 1}
    )
  end

  # protocol 17
  def test_supportability_metrics_for_endpoint_response_time
    NewRelic::Agent.drop_buffered_data

    payload = %w[eggs spam]
    @http_handle.respond_to(:foobar, 'foobar')
    @service.send(:invoke_remote, :foobar, payload)

    assert_metrics_recorded(
      'Supportability/Agent/Collector/foobar/Duration' => {:call_count => 1}
    )
  end

  # protocol 17
  def test_supportability_metrics_for_unsuccessful_endpoint_attempts
    NewRelic::Agent.drop_buffered_data

    @http_handle.respond_to(:metric_data, 'bad format', :code => 400)
    stats_hash = NewRelic::Agent::StatsHash.new

    assert_raises NewRelic::Agent::UnrecoverableServerException do
      @service.metric_data(stats_hash)
    end

    assert_metrics_recorded(
      'Supportability/Agent/Collector/metric_data/Attempts' => {:call_count => 1}
    )
  end

  def test_json_marshaller_handles_responses_from_collector
    marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new

    assert_equal %w[beep boop], marshaller.load('{"return_value": ["beep","boop"]}')
  end

  def test_json_marshaller_returns_nil_on_empty_response_from_collector
    marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new

    assert_nil marshaller.load('')
  end

  def test_json_marshaller_returns_nil_on_nil_response_from_collector
    marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new

    assert_nil marshaller.load(nil)
  end

  def test_raises_serialization_error_if_json_serialization_fails
    ::JSON.stubs(:dump).raises(RuntimeError.new('blah'))
    assert_raises(NewRelic::Agent::SerializationError) do
      @service.send(:invoke_remote, 'wiggle', [{}])
    end
  end

  def test_raises_serialization_error_if_encoding_normalization_fails
    with_config(:normalize_json_string_encodings => true) do
      @http_handle.respond_to(:wiggle, 'hi')
      NewRelic::Agent::EncodingNormalizer.stubs(:normalize_object).raises('blah')
      assert_raises(NewRelic::Agent::SerializationError) do
        @service.send(:invoke_remote, 'wiggle', [{}])
      end
    end
  end

  def test_skips_normalization_if_configured_to
    @http_handle.respond_to(:wiggle, 'hello')
    with_config(:normalize_json_string_encodings => false) do
      NewRelic::Agent::EncodingNormalizer.expects(:normalize_object).never
      @service.send(:invoke_remote, 'wiggle', [{'foo' => 'bar'}])
    end
  end

  def test_json_marshaller_handles_binary_strings
    input_string = (0..255).to_a.pack('C*')
    roundtripped_string = roundtrip_data(input_string)

    assert_equal(Encoding.find('ASCII-8BIT'), input_string.encoding)
    expected = force_to_utf8(input_string.dup)

    assert_equal(expected, roundtripped_string)
  end

  def test_json_marshaller_handles_strings_with_incorrect_encoding
    input_string = (0..255).to_a.pack('C*').force_encoding('UTF-8')
    roundtripped_string = roundtrip_data(input_string)

    assert_equal(Encoding.find('UTF-8'), input_string.encoding)
    expected = input_string.dup.force_encoding('ISO-8859-1').encode('UTF-8')

    assert_equal(expected, roundtripped_string)
  end

  def test_json_marshaller_failure_when_not_normalizing
    input_string = (0..255).to_a.pack('C*')
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
    compressed_json_field = NewRelic::Base64.decode64(base64_encoded_compressed_json_field)
    json_field = Zlib::Inflate.inflate(compressed_json_field)
    field = JSON.parse(json_field)

    assert_equal([expected_string], field)
  end

  def test_compress_request_if_needed_compresses_large_payloads_gzip
    large_payload = 'a' * 65 * 1024
    body, encoding = @service.compress_request_if_needed(large_payload, :foobar)
    zstream = Zlib::Inflate.new(Zlib::MAX_WBITS + 16)

    assert_equal(large_payload, zstream.inflate(body))
    assert_equal('gzip', encoding)
  end

  def test_compress_request_if_needed_compresses_large_payloads_deflate
    with_config(:compressed_content_encoding => 'deflate') do
      large_payload = 'a' * 65 * 1024
      body, encoding = @service.compress_request_if_needed(large_payload, :foobar)

      assert_equal(large_payload, Zlib::Inflate.inflate(body))
      assert_equal('deflate', encoding)
    end
  end

  def test_compress_request_if_needed_passes_thru_small_payloads
    payload = 'a' * 100
    body, encoding = @service.compress_request_if_needed(payload, :foobar)

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
    @service.marshaller.stubs(:dump).raises(StandardError.new('Failed to marshal'))

    refute @service.valid_to_marshal?({})
  end

  def test_not_valid_to_marshal_with_system_stack_error
    @service.marshaller.stubs(:dump).raises(SystemStackError.new)

    refute @service.valid_to_marshal?({})
  end

  def test_supportability_metrics_with_item_count
    NewRelic::Agent.drop_buffered_data

    payload = %w[eggs spam]
    @http_handle.respond_to(:foobar, 'foobar')
    @service.send(:invoke_remote, :foobar, payload, :item_count => 12)

    expected_size_bytes = @service.marshaller.dump(payload).size
    expected_values = {
      :call_count => 1,
      :total_call_time => expected_size_bytes,
      :total_exclusive_time => 12
    }

    assert_metrics_recorded(
      'Supportability/Agent/Collector/foobar/Duration' => {:call_count => 1},
      'Supportability/invoke_remote_serialize' => {:call_count => 1},
      'Supportability/invoke_remote_serialize/foobar' => {:call_count => 1},
      'Supportability/Ruby/Collector/Output/Bytes' => expected_values,
      'Supportability/Ruby/Collector/foobar/Output/Bytes' => expected_values
    )
  end

  def test_supportability_metrics_report_uncompressed_size
    NewRelic::Agent.drop_buffered_data

    payload = 'E' * (NewRelic::Agent::NewRelicService::MIN_BYTE_SIZE_TO_COMPRESS + 20)
    method = :eddie_izzard
    @http_handle.respond_to(method, method.to_s)
    @service.send(:invoke_remote, method, payload, :item_count => 12)

    expected_size_bytes = @service.marshaller.dump(payload).size
    expected_values = {
      :call_count => 1,
      :total_call_time => expected_size_bytes,
      :total_exclusive_time => 12
    }

    assert_metrics_recorded(
      "Supportability/Agent/Collector/#{method}/Duration" => {:call_count => 1},
      'Supportability/invoke_remote_serialize' => {:call_count => 1},
      "Supportability/invoke_remote_serialize/#{method}" => {:call_count => 1},
      'Supportability/Ruby/Collector/Output/Bytes' => expected_values,
      "Supportability/Ruby/Collector/#{method}/Output/Bytes" => expected_values
    )
  end

  def test_max_payload_size_enforced
    NewRelic::Agent.drop_buffered_data
    payload = '.' * (NewRelic::Agent.config[:max_payload_size_in_bytes] + 1)

    assert_raises NewRelic::Agent::UnrecoverableServerException do
      @service.send(:check_post_size, payload, :foobar)
    end

    assert_metrics_recorded(
      'Supportability/Ruby/Collector/foobar/MaxPayloadSizeLimit' => {:call_count => 1}
    )
  end

  def test_supportability_metrics_without_item_count
    NewRelic::Agent.drop_buffered_data

    payload = %w[eggs spam]
    @http_handle.respond_to(:foobar, 'foobar')
    @service.send(:invoke_remote, :foobar, payload)

    expected_size_bytes = @service.marshaller.dump(payload).size
    expected_values = {
      :call_count => 1,
      :total_call_time => expected_size_bytes,
      :total_exclusive_time => 0
    }

    assert_metrics_recorded(
      'Supportability/Agent/Collector/foobar/Duration' => {:call_count => 1},
      'Supportability/invoke_remote_serialize' => {:call_count => 1},
      'Supportability/invoke_remote_serialize/foobar' => {:call_count => 1},
      'Supportability/Ruby/Collector/Output/Bytes' => expected_values,
      'Supportability/Ruby/Collector/foobar/Output/Bytes' => expected_values
    )
  end

  def test_supportability_metrics_with_serialization_failure
    NewRelic::Agent.drop_buffered_data

    payload = %w[eggs spam]
    @http_handle.respond_to(:foobar, 'foobar')
    @service.marshaller.stubs(:dump).raises(StandardError.new)

    assert_raises(NewRelic::Agent::SerializationError) do
      @service.send(:invoke_remote, :foobar, payload)
    end

    expected_values = {:call_count => 1}

    assert_metrics_recorded(
      'Supportability/serialization_failure' => expected_values,
      'Supportability/serialization_failure/foobar' => expected_values
    )

    assert_metrics_not_recorded([
      'Supportability/invoke_remote_serialize',
      'Supportability/invoke_remote_serialize/foobar',
      'Supportability/Ruby/Collector/Output/Bytes',
      'Supportability/Ruby/Collector/foobar/Output/Bytes'
    ])
  end

  def test_force_restart_closes_shared_connections
    @service.establish_shared_connection
    @service.force_restart

    refute_predicate @service, :has_shared_connection?
  end

  def test_force_restart_closes_the_profiles_connection
    @http_handle.respond_to('v1/profiles', '', :code => 202)
    @service.profiles_data('raw-profile-bytes')

    @service.force_restart
    @service.profiles_data('raw-profile-bytes')

    assert_equal 2, @http_handle.calls.count(:start)
  end

  def test_marshal_with_json_only
    with_config(:marshaller => 'pruby') do
      assert_equal 'json', @service.marshaller.format
    end
  end

  def test_headers_from_connect_sent_on_subsequent_posts
    connect_response = {
      'agent_run_id' => 1,
      'request_headers_map' => {
        'X-NR-Run-Token' => 'AFBE4546FEADDEAD1243',
        'X-NR-Metadata' => '12BAED78FC89BAFE1243'
      }
    }

    @http_handle.respond_to(:connect, connect_response)
    @http_handle.respond_to(:foo, ['blah'])

    @service.connect
    @service.send(:invoke_remote, :foo, ['payload'])

    headers = {}
    @http_handle.last_request.each_header { |k, v| headers[k] = v }

    assert_equal 'AFBE4546FEADDEAD1243', headers['x-nr-run-token']
    assert_equal '12BAED78FC89BAFE1243', headers['x-nr-metadata']
  end

  def test_headers_cleared_on_subsequent_connect
    connect_response = {
      'agent_run_id' => 1,
      'request_headers_map' => {
        'X-NR-Run-Token' => 'AFBE4546FEADDEAD1243',
        'X-NR-Metadata' => '12BAED78FC89BAFE1243'
      }
    }

    @http_handle.respond_to(:connect, connect_response)

    @service.connect
    @service.connect

    header_keys = @http_handle.last_request.to_hash.keys

    refute_includes header_keys, 'x-nr-run-token'
    refute_includes header_keys, 'x-nr-metadata'
  end

  def test_filtered_uri
    base = 'https://cdpr_cp2077.com?license_key='
    filtered = @service.send(:filtered_uri, base + @service.send(:license_key))

    assert_equal base + 'license-ke*', filtered
  end

  def test_filtered_uri_short_license_key_is_fully_redacted
    service = NewRelic::Agent::NewRelicService.new('shorty', @server)
    base = 'https://example.com?license_key='
    filtered = service.send(:filtered_uri, base + 'shorty')

    assert_equal base + '******', filtered
  end

  def build_stats_hash(items = {})
    hash = NewRelic::Agent::StatsHash.new
    items.each do |key, value|
      hash.record(NewRelic::MetricSpec.new(key), value)
    end
    hash.harvested_at = Process.clock_gettime(Process::CLOCK_REALTIME)
    hash
  end

  def force_to_utf8(string)
    string.force_encoding('ISO-8859-1').encode('UTF-8')
  end

  def generate_random_byte_sequence(length = 255, encoding = nil)
    bytes = []
    alphabet = (0..255).to_a
    meth = alphabet.respond_to?(:sample) ? :sample : :choice
    length.times { bytes << alphabet.send(meth) }

    string = bytes.pack('C*')
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
    Encoding.list.sample
  end

  def roundtrip_data(data, normalize = true)
    with_config(:normalize_json_string_encodings => normalize) do
      @http_handle.respond_to(:roundtrip, 'roundtrip')
      @service.send(:invoke_remote, 'roundtrip', [data])
      @http_handle.last_request_payload[0]
    end
  end

  def preconnect_response(host)
    {'redirect_host' => host}
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

      def initialize(body, code = 200, message = 'OK')
        @code = code
        @body = body
        @message = message
        @headers = {}
      end

      def [](key)
        @headers[key]
      end
    end

    attr_accessor :read_timeout
    attr_reader :calls, :last_request

    def initialize(name)
      @name = name
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
      'wherever.com'
    end

    def port
      8080
    end

    def create_response_mock(payload, opts = {})
      opts = {
        :code => 200,
        :format => :json
      }.merge(opts)

      klass = Class.new(Net::HTTPResponse::CODE_TO_OBJ[opts[:code].to_s]) {
        include HTTPResponseMock
      }
      klass.new(JSON.dump('return_value' => payload), opts[:code], {})
    end

    def respond_to(method, payload, opts = {})
      case payload
      when Exception then rsp = payload
      else rsp = create_response_mock(payload, opts)
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
        create_response_mock('not found', :code => 404)
      end
    end

    def reset
      @calls = []
      @route_table = {}
      @last_request = nil
    end

    def last_request_payload
      return nil unless @last_request&.body

      content_encoding = @last_request['Content-Encoding']
      body = if content_encoding == 'deflate'
        Zlib::Inflate.inflate(@last_request.body)
      elsif content_encoding == 'gzip'
        zstream = Zlib::Inflate.new(Zlib::MAX_WBITS + 16)
        zstream.inflate(@last_request.body)
      else
        @last_request.body
      end

      uri = URI.parse(@last_request.path)
      params = params_from_query(uri.query)
      format = params['marshal_format'].first
      if format == 'json'
        JSON.load(body)
      else
        Marshal.load(body)
      end
    end

    def params_from_query(query)
      query.split('&').each_with_object({}) do |pair, hash|
        key, val = pair.split('=')
        hash[key] = Array(val)
      end
    end
  end
end
