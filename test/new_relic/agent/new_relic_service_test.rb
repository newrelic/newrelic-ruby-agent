# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'cgi'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/agent/commands/thread_profiler_session'

# Tests of HTTP Keep Alive implementation that require a different setup and
# set of mocks.
class NewRelicServiceKeepAliveTest < Test::Unit::TestCase
  def setup
    @server = NewRelic::Control::Server.new('somewhere.example.com',
                                            30303, '10.10.10.10')
    @service = NewRelic::Agent::NewRelicService.new('license-key', @server)
  end

  def stub_net_http_handle(overrides = {})
    defaults = { :start => true, :finish => true, :address => '10.10.10.10', :port => 30303, :started? => true }
    stub('http_handle', defaults.merge(overrides))
  end

  def test_session_handles_timeouts_opening_connection_gracefully
    conn = stub_net_http_handle(:started? => false)
    conn.stubs(:start).raises(Timeout::Error)
    conn.stubs(:finish).raises(RuntimeError)
    @service.stubs(:create_http_connection).returns(conn)

    block_ran = false

    assert_raises(Timeout::Error) do
      @service.session do
        block_ran = true
      end
    end

    assert(!block_ran, "Expected block passed to #session to have not run")
  end

  def test_session_block_reuses_http_handle
    handle1 = stub_net_http_handle
    handle2 = stub_net_http_handle
    @service.stubs(:create_http_connection).returns(handle1, handle2)

    block_ran = false
    @service.session do
      block_ran = true
      assert(@service.http_connection)

      # check we get the same object back each time we call http_connection in the block
      assert_equal(@service.http_connection.object_id, handle1.object_id)
      assert_equal(@service.http_connection.object_id, handle1.object_id)
    end
    assert(block_ran)
  end

  def test_multiple_http_handles_are_used_outside_session_block
    handle1 = stub_net_http_handle
    handle2 = stub_net_http_handle
    @service.stubs(:create_http_connection).returns(handle1, handle2)
    assert_equal(@service.http_connection.object_id, handle1.object_id)
    assert_equal(@service.http_connection.object_id, handle2.object_id)
  end


  def test_session_starts_and_finishes_http_session
    handle1 = stub_net_http_handle
    handle1.expects(:start).once
    handle1.expects(:finish).once
    @service.stubs(:create_http_connection).returns(handle1)

    block_ran = false
    @service.session do
      block_ran = true
      # mocks expect #start and #finish to be called.  This is how Net::HTTP
      # implements keep alive
    end
    assert(block_ran)
  end

end

class NewRelicServiceTest < Test::Unit::TestCase
  def initialize(*_)
    [ :HTTPSuccess,
      :HTTPUnauthorized,
      :HTTPNotFound,
      :HTTPRequestEntityTooLarge,
      :HTTPUnsupportedMediaType ].each do |class_name|
      extend_with_mock(class_name)
    end
    super
  end

  def extend_with_mock(class_name)
    if !self.class.const_defined?(class_name)
      klass = self.class.const_set(class_name,
                Class.new(Object.const_get(:Net).const_get(class_name)))
      klass.class_eval { include HTTPResponseMock }
    end
  end
  protected :extend_with_mock

  def setup
    @server = NewRelic::Control::Server.new('somewhere.example.com',
                                            30303, '10.10.10.10')
    @service = NewRelic::Agent::NewRelicService.new('license-key', @server)
    @http_handle = HTTPHandle.new
    @service.stubs(:create_http_connection).returns(@http_handle)

    @http_handle.respond_to(:get_redirect_host, 'localhost')
    connect_response = {
      'config' => 'some config directives',
      'agent_run_id' => 1
    }
    @http_handle.respond_to(:connect, connect_response)

    @reverse_encoder = Module.new do
      def self.encode(data)
        data.reverse
      end
    end
  end

  def test_cert_file_path
    assert @service.cert_file_path
    assert_equal File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'cert', 'cacert.pem')), @service.cert_file_path
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

  def test_connect_resets_cached_ip_address
    assert_equal '10.10.10.10', @service.collector.ip
    @service.connect
    assert_equal 'localhost', @service.collector.ip # 'localhost' resolves to nil
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
    @service.expects(:fill_metric_id_cache).with(dummy_rsp)
    response = @service.metric_data(stats_hash)

    assert_equal 4, @http_handle.last_request_payload.size
    assert_equal dummy_rsp, response
  end

  def test_metric_data_sends_harvest_timestamps
    @http_handle.respond_to(:metric_data, 'foo')
    @service.stubs(:fill_metric_id_cache)

    t0 = freeze_time
    stats_hash = NewRelic::Agent::StatsHash.new
    stats_hash.harvested_at = Time.now

    @service.metric_data(stats_hash)
    payload = @http_handle.last_request_payload
    _, last_harvest_timestamp, harvest_timestamp, _ = payload
    assert_equal(t0.to_f, harvest_timestamp)

    t1 = advance_time(10)
    stats_hash.harvested_at = t1

    @service.metric_data(stats_hash)
    payload = @http_handle.last_request_payload
    _, last_harvest_timestamp, harvest_timestamp, _ = payload
    assert_equal(t1.to_f, harvest_timestamp)
    assert_equal(t0.to_f, last_harvest_timestamp)
  end

  def test_fill_metric_id_cache_from_collect_response
    response = [[{"scope"=>"Controller/blogs/index", "name"=>"Database/SQL/other"}, 1328],
                [{"scope"=>"", "name"=>"WebFrontend/QueueTime"}, 10],
                [{"scope"=>"", "name"=>"ActiveRecord/Blog/find"}, 1017]]

    @service.send(:fill_metric_id_cache, response)

    cache = @service.metric_id_cache
    assert_equal 1328, cache[NewRelic::MetricSpec.new('Database/SQL/other', 'Controller/blogs/index')]
    assert_equal 10,   cache[NewRelic::MetricSpec.new('WebFrontend/QueueTime')]
    assert_equal 1017, cache[NewRelic::MetricSpec.new('ActiveRecord/Blog/find')]
  end

  def test_caches_metric_ids_for_future_use
    dummy_rsp = [[{ 'name' => 'a', 'scope' => '' }, 42]]
    @http_handle.respond_to(:metric_data, dummy_rsp)

    hash = build_stats_hash('a' => 1)

    @service.metric_data(hash)

    hash = build_stats_hash('a' => 1)
    stats = hash[NewRelic::MetricSpec.new('a')]

    results = @service.build_metric_data_array(hash)
    assert_nil(results.first.metric_spec)
    assert_equal(stats, results.first.stats)
    assert_equal(42, results.first.metric_id)
  end

  def test_metric_data_tracks_last_harvest_time
    t0 = freeze_time

    @http_handle.respond_to(:metric_data, [])

    hash = build_stats_hash('a' => 1)
    advance_time(1)
    @service.metric_data(hash)
    assert_equal(t0, @service.last_metric_harvest_time)

    t1 = advance_time(60)
    hash = build_stats_hash('a' => 1)
    @service.metric_data(hash)
    assert_equal(t1, @service.last_metric_harvest_time)
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
    response = @service.analytic_event_data([])
    assert_equal 'some analytic events', response
  end

  # Although thread profiling is only available in some circumstances, the
  # service communication doesn't care about that at all
  def test_profile_data
    @http_handle.respond_to(:profile_data, 'profile' => 123)
    response = @service.profile_data([])
    assert_equal({ "profile" => 123 }, response)
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
    assert_raise NewRelic::Agent::ServerConnectionException do
      @service.send(:invoke_remote, :bogus_method)
    end
  end

  def test_should_connect_to_proxy_only_once_per_run
    @service.expects(:get_redirect_host).once

    @service.connect
    @http_handle.respond_to(:metric_data, 0)
    @service.stubs(:fill_metric_id_cache)
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
    assert_raise NewRelic::Agent::LicenseException do
      @service.get_redirect_host
    end
  end

  # protocol 9
  def test_should_raise_exception_on_413
    @http_handle.respond_to(:metric_data, 'too big', :code => 413)
    assert_raise NewRelic::Agent::UnrecoverableServerException do
      stats_hash = NewRelic::Agent::StatsHash.new
      @service.metric_data(stats_hash)
    end
  end

  # protocol 9
  def test_should_raise_exception_on_415
    @http_handle.respond_to(:metric_data, 'too big', :code => 415)
    assert_raise NewRelic::Agent::UnrecoverableServerException do
      stats_hash = NewRelic::Agent::StatsHash.new
      @service.metric_data(stats_hash)
    end
  end

  if NewRelic::LanguageSupport.using_version?('1.9')
    def test_json_marshaller_handles_responses_from_collector
      marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
      assert_equal ['beep', 'boop'], marshaller.load('{"return_value": ["beep","boop"]}')
    end

    def test_json_marshaller_handles_errors_from_collector
      marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
      assert_raise(NewRelic::Agent::NewRelicService::CollectorError,
                   'JavaCrash: error message') do
        marshaller.load('{"exception": {"message": "error message", "error_type": "JavaCrash"}}')
      end
    end

    def test_use_pruby_marshaller_if_error_using_json
      json_marshaller = NewRelic::Agent::NewRelicService::JsonMarshaller.new
      @service.instance_variable_set(:@marshaller, json_marshaller)
      JSON.stubs(:dump).raises(RuntimeError.new('blah'))
      @http_handle.respond_to(:transaction_sample_data, 'ok', :format => :pruby)

      @service.transaction_sample_data([])

      assert_equal('NewRelic::Agent::NewRelicService::PrubyMarshaller',
                   @service.marshaller.class.name)
    end
  end

  def test_pruby_marshaller_handles_errors_from_collector
    marshaller = NewRelic::Agent::NewRelicService::PrubyMarshaller.new
    assert_raise(NewRelic::Agent::NewRelicService::CollectorError, 'error message') do
      marshaller.load(Marshal.dump({"exception" => {"message" => "error message",
                                       "error_type" => "JavaCrash"}}))
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

    prepared = marshaller.prepare(dummy, :encoder => @reverse_encoder)
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
    prepared = marshaller.prepare(dummy, :encoder => @reverse_encoder)
    assert_equal([[['dcba']]], prepared)
  end

  def test_marshaller_handles_known_errors
    error_data = {
      'error_type' => 'NewRelic::Agent::ForceRestartException',
      'message'    => 'test'
    }
    error = @service.marshaller.parsed_error(error_data)
    assert_equal NewRelic::Agent::ForceRestartException, error.class
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

  def test_build_metric_data_array_uses_metric_id_cache_if_possible
    hash = NewRelic::Agent::StatsHash.new

    spec1 = NewRelic::MetricSpec.new('foo')
    spec2 = NewRelic::MetricSpec.new('bar')
    hash.record(spec1, 1)
    hash.record(spec2, 1)

    @service.stubs(:metric_id_cache).returns({ spec1 => 42 })
    metric_data_array = @service.build_metric_data_array(hash)

    assert_equal(2, metric_data_array.size)

    metric_data1 = metric_data_array.find { |md| md.metric_id == 42 }
    metric_data2 = metric_data_array.find { |md| md.metric_spec == spec2 }
    assert_nil(metric_data1.metric_spec)
    assert_nil(metric_data2.metric_id)
  end

  def test_build_metric_data_array_omits_empty_stats
    hash = NewRelic::Agent::StatsHash.new

    spec1 = NewRelic::MetricSpec.new('foo')
    spec2 = NewRelic::MetricSpec.new('bar')
    hash.record(spec1, 1)
    hash[spec2] = NewRelic::Agent::Stats.new()

    metric_data_array = @service.build_metric_data_array(hash)
    assert_equal(1, metric_data_array.size)

    metric_data = metric_data_array.first
    assert_equal(spec1, metric_data.metric_spec)
  end

  def build_stats_hash(items={})
    hash = NewRelic::Agent::StatsHash.new
    items.each do |key, value|
      hash.record(NewRelic::MetricSpec.new(key), value)
    end
    hash.harvested_at = Time.now
    hash
  end

  class HTTPHandle
    attr_accessor :read_timeout, :route_table

    def initialize
      reset
    end

    def respond_to(method, payload, opts={})
      if NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported?
        format = :json
      else
        format = :pruby
      end

      opts = {
        :code => 200,
        :format => format
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

      if opts[:format] == :json
        register(klass.new(JSON.dump('return_value' => payload), opts[:code])) do |request|
          request.path.include?(method.to_s)
        end
      else
        register(klass.new(Marshal.dump('return_value' => payload), opts[:code])) do |request|
          request.path.include?(method.to_s)
        end
      end
    end

    def register(response, &block)
      @route_table[block] = response
    end

    def request(*args)
      @last_request = args.first
      @route_table.each_pair do |condition, response|
        if condition.call(args[0])
          return response
        end
      end
      HTTPNotFound.new('not found', 404)
    end

    def reset
      @route_table = {}
      @last_request = nil
    end

    def last_request
      @last_request
    end

    def last_request_payload
      return nil unless @last_request && @last_request.body
      uri = URI.parse(@last_request.path)
      params = CGI.parse(uri.query)
      format = params['marshal_format'].first
      if format == 'json'
        JSON.load(@last_request.body)
      else
        Marshal.load(@last_request.body)
      end
    end
  end

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
end
