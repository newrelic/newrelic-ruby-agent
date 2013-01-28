require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/agent/thread_profiler'

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
    NewRelic::Control.instance.stubs(:http_connection).returns(@http_handle)

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
    assert_nil @service.collector.ip # 'localhost' resolves to nil
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
    @http_handle.respond_to(:metric_data, 'met rick date uhhh')
    response = @service.metric_data((Time.now - 60).to_f, Time.now.to_f, {})
    assert_equal 'met rick date uhhh', response
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


# Thread profiling only available in certain versions
if NewRelic::Agent::ThreadProfiler.is_supported?
  def test_profile_data
    @http_handle.respond_to(:profile_data, 'profile' => 123)
    response = @service.profile_data(NewRelic::Agent::ThreadProfile.new(0, 0, 0, true))
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
    response = @service.agent_command_results(4200)
    assert_equal({}, response)
  end

  def test_agent_command_results_with_errors
    @http_handle.respond_to(:agent_command_results, [123])
    response = @service.agent_command_results(4200, 'Boo!')
    assert_equal [123], response
  end
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
    @service.metric_data((Time.now - 60).to_f, Time.now.to_f, {})

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
      @service.metric_data((Time.now - 60).to_f, Time.now.to_f, {})
    end
  end

  # protocol 9
  def test_should_raise_exception_on_415
    @http_handle.respond_to(:metric_data, 'too big', :code => 415)
    assert_raise NewRelic::Agent::UnrecoverableServerException do
      @service.metric_data((Time.now - 60).to_f, Time.now.to_f, {})
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
      @route_table.each_pair do |condition, response|
        if condition.call(args[0])
          return response
        end
      end
      HTTPNotFound.new('not found', 404)
    end

    def reset
      @route_table = {}
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
