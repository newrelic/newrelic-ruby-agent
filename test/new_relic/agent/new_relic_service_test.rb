require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))

class NewRelicServiceTest < Test::Unit::TestCase
  def initialize(*_)
    [ :HTTPSuccess,
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
    @http_handle.respond_to(:connect, {'agent_run_id' => 1})

    @service.connect
    assert_equal 'somewhere.example.com', @service.collector.name
  end

  def test_connect_sets_agent_id
    @http_handle.reset
    @http_handle.respond_to(:get_redirect_host, 'localhost')
    @http_handle.respond_to(:connect, {'agent_run_id' => 666})

    @service.connect
    assert_equal 666, @service.agent_id
  end

  def test_get_redirect_host
    host = @service.get_redirect_host
    assert_equal 'localhost', host
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
    response = @service.metric_data(Time.now - 60, Time.now, {})
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
    @http_handle.respond_to(:metric_data, '0')
    @service.metric_data(Time.now - 60, Time.now, {})

    @http_handle.respond_to(:transaction_sample_data, '1')
    @service.transaction_sample_data([])

    @http_handle.respond_to(:sql_trace_data, '2')
    @service.sql_trace_data([])
  end

  # protocol 9
  def test_should_raise_exception_on_413
    @http_handle.respond_to(:metric_data, 'too big', 413)
    assert_raise NewRelic::Agent::UnrecoverableServerException do
      @service.metric_data(Time.now - 60, Time.now, {})
    end
  end

  # protocol 9
  def test_should_raise_exception_on_415
    @http_handle.respond_to(:metric_data, 'too big', 415)
    assert_raise NewRelic::Agent::UnrecoverableServerException do
      @service.metric_data(Time.now - 60, Time.now, {})
    end
  end

  class HTTPHandle
    attr_accessor :read_timeout, :route_table

    def initialize
      reset
    end

    def respond_to(method, payload, code=200)
      klass = HTTPSuccess
      if code == 413
        klass = HTTPRequestEntityTooLarge
      elsif code == 415
        klass = HTTPUnsupportedMediaType
      elsif code >= 400
        klass = HTTPServerError
      end

      register(klass.new(Marshal.dump(payload), code)) do |request|
        request.path.include?(method.to_s)
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
