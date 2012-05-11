require 'rubygems'
require 'rack'
require 'uri'
require 'socket'
require 'timeout'
require 'ostruct'

module NewRelic
  class FakeCollector
    attr_accessor :agent_data, :mock
    
    def initialize
      @id_counter = 0
      @base_expectations = {
        'get_redirect_host'       => 'localhost',
        'connect'                 => { 'agent_run_id' => agent_run_id },
        'metric_data'             => { 'Some/Metric/Spec' => 1 },
        'sql_trace_data'          => nil,
        'transaction_sample_data' => nil,
        'error_data'              => nil,
        'shutdown'                => nil,
      }
      reset
    end

    def agent_run_id
      @id_counter += 1
    end
    
    def call(env)
      req = ::Rack::Request.new(env)
      res = ::Rack::Response.new
      uri = URI.parse(req.url)
      if uri.path =~ /agent_listener\/\d+\/.+\/(\w+)/
        method = $1
        if @mock.keys.include? method
          res.write Marshal.dump(@mock[method])
        else
          res.status = 500
          res.write "Method not found"
        end
        run_id = uri.query =~ /run_id=(\d+)/ ? $1 : nil
        req.body.rewind
        @agent_data << OpenStruct.new(:action => method,
                                      :body   => Marshal.load(req.body.read),
                                      :run_id => run_id)
      end
      res.finish
    end

    def run(port=30303)
      if is_port_available?('127.0.0.1', port)
        @thread = Thread.new do
          ::Rack::Handler::WEBrick.run(self, :Port => port)
        end
        loop do
          break if !is_port_available?('127.0.0.1', port)
          sleep 0.01
        end
      end
    end

    def stop
      ::Rack::Handler::WEBrick.shutdown
      @thread.join
    end

    def reset
      @mock = @base_expectations.dup
      @id_counter = 0
      @agent_data = []
    end
    
    def is_port_available?(ip, port)
      begin
        Timeout::timeout(1) do
          begin
            s = TCPSocket.new(ip, port)
            s.close
            return false
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            return true
          end
        end
      rescue Timeout::Error
      end
      
      return true
    end
  end
end

if $0 == __FILE__
  require 'test/unit'
  require 'net/http'
  
  class FakeCollectorTest < Test::Unit::TestCase
    def setup
      @collector = NewRelic::FakeCollector.new
      @collector.run
    end

    def teardown
      @collector.stop
    end
    
    def test_get_redirect
      @collector.mock['get_redirect_host'] = 'test.example.com'
      response = invoke('get_redirect_host')
      
      assert_equal 'test.example.com', response
      assert_equal 'get_redirect_host', @collector.agent_data[0].action
    end
    
    def test_connect
      response = invoke('connect')
      
      assert_equal 1, response['agent_run_id']
      assert_equal 'connect', @collector.agent_data[0].action
    end

    def test_metric_data
      response = invoke('metric_data?run_id=1',
                        {'Foo/Bar' => [1,2,3], 'Baz/Cux' => [4,5,6]})
      
      assert_equal 1, response['Some/Metric/Spec']
      post = @collector.agent_data[0]
      assert_equal 'metric_data', post.action
      assert_equal({'Foo/Bar' => [1,2,3], 'Baz/Cux' => [4,5,6]}, post.body)
      assert_equal 1, post.run_id.to_i
    end

    def test_sql_trace_data
      response = invoke('sql_trace_data?run_id=2',
                        ['trace', 'trace', 'trace'])

      assert_nil response
      post = @collector.agent_data[0]
      assert_equal 'sql_trace_data', post.action
      assert_equal ['trace', 'trace', 'trace'], post.body
      assert_equal 2, post.run_id.to_i
    end

    def test_transaction_sample_data
      response = invoke('transaction_sample_data?run_id=3',
                        ['node', ['node', 'node'], 'node'])

      assert_nil response
      post = @collector.agent_data[0]
      assert_equal 'transaction_sample_data', post.action
      assert_equal ['node', ['node', 'node'], 'node'], post.body
      assert_equal 3, post.run_id.to_i
    end
    
    def test_error_data
      response = invoke('error_data?run_id=4', ['error'])
      
      assert_nil response
      post = @collector.agent_data[0]
      assert_equal 'error_data', post.action
      assert_equal ['error'], post.body
    end
    
    def test_shutdown
      response = invoke('shutdown?run_id=1')

      assert_nil response
      assert_equal 'shutdown', @collector.agent_data[0].action
    end

    def test_multiple_invokations
      pid = Process.fork do
        invoke('get_redirect_host')
        invoke('connect')
        invoke('metric_data?run_id=1')
        invoke('transaction_sample_data?run_id=1')
        invoke('shutdown?run_id=1')
      end
      invoke('get_redirect_host')
      invoke('connect')
      invoke('metric_data?run_id=2')
      invoke('transaction_sample_data?run_id=2')
      invoke('shutdown?run_id=2')

      Process.wait(pid)
      
      expected = ['get_redirect_host', 'connect', 'metric_data',
                  'transaction_sample_data', 'shutdown',
                  'get_redirect_host', 'connect', 'metric_data',
                  'transaction_sample_data', 'shutdown']
      assert_equal expected.sort, @collector.agent_data.map(&:action).sort
    end

    def test_reset
      @collector.mock['get_redirect_host'] = 'never!'
      @collector.reset
      assert_equal 'localhost', @collector.mock['get_redirect_host']
    end
   
    def invoke(method, post={}, code=200)
      uri = URI.parse("http://127.0.0.1:30303/agent_listener/8/12345/#{method}")
      request = Net::HTTP::Post.new("#{uri.path}?#{uri.query}")
      request.body = Marshal.dump(post)
      response = Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(request)
      end
      Marshal.load(response.body)
    end
  end
end
