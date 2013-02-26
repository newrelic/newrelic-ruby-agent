# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rubygems'
require 'rack'
require 'uri'
require 'socket'
require 'timeout'
require 'ostruct'

require 'json' if RUBY_VERSION >= '1.9'

module NewRelic
  class FakeCollector
    attr_accessor :agent_data, :mock

    def initialize
      @id_counter = 0
      @base_expectations = {
        'get_redirect_host'       => [200, {'return_value' => 'localhost'}],
        'connect'                 => [200, {'return_value' => {"agent_run_id" => agent_run_id}}],
        'get_agent_commands'      => [200, {'return_value' => []}],
        'metric_data'             => [200, {'return_value' => [[{'name' => 'Some/Metric/Spec'}, 1]]}],
        'sql_trace_data'          => [200, {'return_value' => nil}],
        'transaction_sample_data' => [200, {'return_value' => nil}],
        'error_data'              => [200, {'return_value' => nil}],
        'shutdown'                => [200, {'return_value' => nil}]
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
        format = json_format?(uri) && RUBY_VERSION >= '1.9' ? :json : :pruby
        if @mock.keys.include? method
          res.status = @mock[method][0]
          if format == :json
            res.write JSON.dump(@mock[method][1])
          else
            res.write Marshal.dump(@mock[method][1])
          end
        else
          res.status = 500
          res.write "Method not found"
        end
        run_id = uri.query =~ /run_id=(\d+)/ ? $1 : nil
        req.body.rewind

        begin
          raw_body = req.body.read
          raw_body = Zlib::Inflate.inflate(raw_body) if req.env["HTTP_CONTENT_ENCODING"] == "deflate"

          body = if format == :json
            body = JSON.load(raw_body)
          else
            body = Marshal.load(raw_body)
          end
        rescue => err
          body = "UNABLE TO DECODE BODY: #{raw_body}"
        end

        @agent_data << AgentPost.create(:action       => method,
                                        :body         => body,
                                        :run_id       => run_id,
                                        :format       => format)
      end
      res.finish
    end

    def json_format?(uri)
      uri.query && uri.query.include?('marshal_format=json')
    end

    # We generate a "unique" port for ourselves based off our pid
    # If this logic changes, look for multiverse newrelic.yml files to update
    # with it duplicated (since we can't easily pull this ruby into a yml)
    def self.determine_port
      30_000 + ($$ % 10_000)
    end

    def determine_port
      FakeCollector.determine_port
    end

    @seen_port_failure = false

    def run(port=nil)
      port ||= determine_port
      return if @thread && @thread.alive?
      serve_on_port(port) do
        @thread = Thread.new do
          begin
          ::Rack::Handler::WEBrick.run(self,
                                       :Port => port,
                                       :Logger => ::WEBrick::Log.new("/dev/null"),
                                       :AccessLog => [ ['/dev/null', ::WEBrick::AccessLog::COMMON_LOG_FORMAT] ]
                                      )
          rescue Errno::EADDRINUSE => ex
            msg = "Port #{port} for FakeCollector was in use"
            if !@seen_port_failure
              # This is slow, so only do it the first collision we detect
              lsof = `lsof | grep #{port}`
              msg = msg + "\n#{lsof}"
              @seen_port_failure = true
            end

            raise Errno::EADDRINUSE.new(msg)
          end
        end
        @thread.abort_on_exception = true
      end
    end

    def serve_on_port(port)
      port ||= determine_port
      if is_port_available?('127.0.0.1', port)
        yield
        loop do
          break if !is_port_available?('127.0.0.1', port)
          sleep 0.01
        end
      end
    end

    def stop
      return unless @thread.alive?
      ::Rack::Handler::WEBrick.shutdown
      @thread.join
      reset
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

    def calls_for(method)
      @agent_data.select {|d| d.action == method }
    end

    def reported_stats_for_metric(name, scope=nil)
      calls_for('metric_data').map do |post|
        post.body[3].find do |metric_record|
          metric_record[0]['name'] == name &&
            (!scope || metric_record[0]['scope'] == scope)
        end
      end.compact.map{|m| m[1]}
    end

    class AgentPost
      attr_accessor :action, :body, :run_id, :format
      def initialize(opts={})
        @action = opts[:action]
        @body   = opts[:body]
        @run_id = opts[:run_id]
        @format = opts[:format]
      end

      def self.create(opts={})
        case opts[:action]
        when 'connect'
          ConnectPost.new(opts)
        when 'metric_data'
          AgentPost.new(opts)
        when 'profile_data'
          ProfileDataPost.new(opts)
        when 'sql_trace_data'
          SqlTraceDataPost.new(opts)
        when 'transaction_sample_data'
          TransactionSampleDataPost.new(opts)
        else
          new(opts)
        end
      end

      def [](key)
        @body[key]
      end

      def unblob(blob)
        return unless blob
        JSON.load(Zlib::Inflate.inflate(Base64.decode64(blob)))
      end
    end

    class ConnectPost < AgentPost
      def initialize(opts={})
        super
        @body = @body[0]
      end
    end

    class ProfileDataPost < AgentPost
      def initialize(opts={})
        super
        @body[1][0][4] = unblob(@body[1][0][4]) if @format == :json
      end
    end

    class SqlTraceDataPost < AgentPost
      def initialize(opts={})
        super
        @body[0][0][9] = unblob(@body[0][0][9]) if @format == :json
      end
    end

    class TransactionSampleDataPost < AgentPost
      def initialize(opts={})
        super
        @body[4] = unblob(@body[4]) if @format == :json
      end

      def metric_name
        @body[1][0][2]
      end
    end
  end

  # might we need this?  I'll just leave it here for now
  class FakeCollectorProcess < FakeCollector
    def run(port)
      serve_on_port(port) do
        @pid = Process.fork do
          ::Rack::Handler::WEBrick.run(self, :Port => port)
        end
      end
    end

    def stop
      return unless @pid
      Process.kill('QUIT', @pid)
      Process.wait(@pid)
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
      @collector.mock['get_redirect_host'] = [200, 'test.example.com']
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

    def test_transaction_sample_data_json
      response = invoke('transaction_sample_data?run_id=3&marshal_format=json',
                        '["node",["node","node"],"node"]')

      assert_equal '', response
      post = @collector.agent_data[0]
      assert_equal 'transaction_sample_data', post.action
      assert_equal '["node",["node","node"],"node"]', post.body
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
      @collector.mock['get_redirect_host'] = [200, 'never!']
      @collector.reset
      assert_equal [200, 'localhost'], @collector.mock['get_redirect_host']
    end

    def invoke(method, post={}, code=200)
      uri = URI.parse("http://127.0.0.1:#{@collector.determine_port}/agent_listener/8/12345/#{method}")
      request = Net::HTTP::Post.new("#{uri.path}?#{uri.query}")
      if uri.query && uri.query.include?('marshal_format=json')
        request.body = JSON.dump(post)
      else
        request.body = Marshal.dump(post)
      end
      response = Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(request)
      end
      if uri.query && uri.query.include?('marshal_format=json')
        JSON.load(response.body)
      else
        Marshal.load(response.body)
      end
    end
  end
end

