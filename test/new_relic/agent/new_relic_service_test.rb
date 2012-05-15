require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))

class NewRelicServiceTest < Test::Unit::TestCase
  def setup
    @server = NewRelic::Control::Server.new('127.0.0.1', 30303)    
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

  def test_connect_sets_agent_id_and_config_data
    response = @service.connect
    assert_equal 1, response['agent_run_id']
    assert_equal 'some config directives', response['config']
  end

  def test_connect_sets_redirect_host
    assert_equal '127.0.0.1', @service.collector.name
    @service.connect    
    assert_equal 'localhost', @service.collector.name
  end

  def test_connect_uses_proxy_collector_if_no_redirect_host
    @http_handle.reset
    @http_handle.respond_to(:get_redirect_host, nil)
    @http_handle.respond_to(:connect, {'agent_run_id' => 1})

    @service.connect
    assert_equal '127.0.0.1', @service.collector.name
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
    @http_handle.respond_to(:shutdown, 'shut this bird down')
    response = @service.shutdown(Time.now)
    assert_equal 'shut this bird down', response
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
    NewRelic::Control.instance['timeout'] = 600
    service = NewRelic::Agent::NewRelicService.new('abcdef', @server)
    assert_equal 600, service.request_timeout
  end

  def test_should_throw_received_errors
    assert_raise NewRelic::Agent::ServerConnectionException do
      @service.send(:invoke_remote, :bogus_method)
    end
  end

  class HTTPHandle
    attr_accessor :read_timeout, :route_table

    def initialize
      reset
    end

    def respond_to(method, payload)
      register(HTTPResponse.new(Marshal.dump(payload))) do |request|
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
      HTTPFailure.new('not found', 404)
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

  HTTPResponse = Class.new(Net::HTTPOK)
  HTTPResponse.class_eval { include HTTPResponseMock }
  HTTPFailure = Class.new(Net::HTTPError)
  HTTPFailure.class_eval { include HTTPResponseMock }
end
