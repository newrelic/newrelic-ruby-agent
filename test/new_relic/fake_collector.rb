# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rubygems'
require 'rack'
require 'uri'
require 'socket'
require 'timeout'
require 'ostruct'
require 'fake_server'

require 'json' if RUBY_VERSION >= '1.9'

module NewRelic
  class FakeCollector < FakeServer
    attr_accessor :agent_data, :mock

    def initialize
      super
      @id_counter = 0
      @base_expectations = {
        'get_redirect_host'       => [200, {'return_value' => 'localhost'}],
        'connect'                 => [200, {'return_value' => {"agent_run_id" => agent_run_id}}],
        'get_agent_commands'      => [200, {'return_value' => []}],
        'agent_command_results'   => [200, {'return_value' => []}],
        'metric_data'             => [200, {'return_value' => [[{'name' => 'Some/Metric/Spec'}, 1]]}],
        'sql_trace_data'          => [200, {'return_value' => nil}],
        'transaction_sample_data' => [200, {'return_value' => nil}],
        'error_data'              => [200, {'return_value' => nil}],
        'profile_data'            => [200, {'return_value' => nil}],
        'shutdown'                => [200, {'return_value' => nil}],
        'analytic_event_data'     => [200, {'return_value' => nil}]
      }
      reset
    end

    def agent_run_id
      @id_counter += 1
    end

    def reset
      @mock = @base_expectations.dup
      @id_counter = 0
      @agent_data = []
    end

    def stub(method, return_value, status=200)
      self.mock[method] = [status, {'return_value' => return_value}]
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

    def app
      self
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
          MetricDataPost.new(opts)
        when 'profile_data'
          ProfileDataPost.new(opts)
        when 'sql_trace_data'
          SqlTraceDataPost.new(opts)
        when 'transaction_sample_data'
          TransactionSampleDataPost.new(opts)
        when 'analytic_event_data'
          AnalyticEventDataPost.new(opts)
        else
          new(opts)
        end
      end

      def [](key)
        @body[key]
      end

      def unblob(blob)
        self.class.unblob(blob)
      end

      def self.unblob(blob)
        return unless blob
        JSON.load(Zlib::Inflate.inflate(Base64.decode64(blob)))
      end
    end


    class MetricDataPost < AgentPost
      def initialize(opts={})
        super
      end

      def metrics
        @body[3]
      end

      def metric_names
        metrics.map {|m| m[0]["name"] }
      end
    end

    class ConnectPost < AgentPost
      def initialize(opts={})
        super
        @body = @body[0]
      end
    end

    class ProfileDataPost < AgentPost
      attr_accessor :sample_count, :traces
      def initialize(opts={})
        super
        @sample_count = @body[1][0][3]
        @body[1][0][4] = unblob(@body[1][0][4]) if @format == :json
        @traces = @body[1][0][4]
      end
    end

    class SqlTraceDataPost < AgentPost
      def initialize(opts={})
        super
        @body[0][0][9] = unblob(@body[0][0][9]) if @format == :json
      end
    end

    class TransactionSampleDataPost < AgentPost
      class SubmittedTransactionTrace
        def initialize(body, format)
          @body = body
          @format = format
        end

        def metric_name
          @body[2]
        end

        def uri
          @body[3]
        end

        def tree
          SubmittedTransactionTraceTree.new(@body[4], @format)
        end

        def xray_id
          @body[8]
        end
      end

      class SubmittedTransactionTraceTree
        def initialize(body, format)
          @body = body
          @body = AgentPost.unblob(@body) if format == :json
        end

        def request_params
          normalize_params(@body[1])
        end

        def custom_params
          normalize_params(@body[2])
        end

        # Pruby marshalled stuff ends up with symbol keys.  JSON ends up with
        # strings. This makes writing tests on the params annoying. Normalize
        # it all to string keys.
        def normalize_params(params)
          result = {}
          @body[2].each do |k,v|
            result[k.to_s] = v
          end
          result
        end
      end

      def initialize(opts={})
        super
        @body[4] = unblob(@body[4]) if @format == :json
      end

      def samples
        @samples ||= @body[1].map { |s| SubmittedTransactionTrace.new(s, @format) }
      end

      def metric_name
        samples.first.metric_name
      end
    end
    class AnalyticEventDataPost < AgentPost

      def initialize(opts={})
        opts[:run_id] = opts[:body].shift
        opts[:body] = opts[:body].shift

        super
      end
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

    def test_analytic_event_data
      events = [
        {
          'type' => 'Transaction',
          'name' => 'Controller/foo/bar',
          'duration' => '718',
          'timestamp' => 1368489547.888435
        }
      ]
      response = invoke('analytic_event_data', [33, events])

      assert_nil response['return_value']
      post = @collector.agent_data[0]
      assert_equal 'analytic_event_data', post.action
      assert_equal events, post.body
      assert_equal 33, post.run_id.to_i
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
