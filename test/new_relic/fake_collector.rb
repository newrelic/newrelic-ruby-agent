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
    class Response
      attr_reader :status, :body

      def initialize(status, body)
        @default_status = status
        @default_body = body
        @remaining = nil
        revert
      end

      def override(status, body)
        @status = status
        @body = body
        self
      end

      def revert
        @status = @default_status
        @body = @default_body
        @remaining = nil
      end

      def once
        @remaining = 1
        self
      end

      def evaluate
        if @remaining == 0
          revert
        elsif @remaining
          @remaining -= 1
        end
        resolved_body = @body.respond_to?(:call) ? @body.call : @body
        [@status, resolved_body]
      end
    end

    attr_accessor :agent_data, :mock

    def initialize
      super
      @id_counter = 0
      @mock = {
        'get_redirect_host'       => Response.new(200, {'return_value' => 'localhost'}),
        'connect'                 => Response.new(200, Proc.new { {'return_value' => {"agent_run_id" => agent_run_id}} }),
        'get_agent_commands'      => Response.new(200, {'return_value' => []}),
        'agent_command_results'   => Response.new(200, {'return_value' => []}),
        'metric_data'             => Response.new(200, {'return_value' => [[{'name' => 'Some/Metric/Spec'}, 1]]}),
        'sql_trace_data'          => Response.new(200, {'return_value' => nil}),
        'transaction_sample_data' => Response.new(200, {'return_value' => nil}),
        'error_data'              => Response.new(200, {'return_value' => nil}),
        'profile_data'            => Response.new(200, {'return_value' => nil}),
        'shutdown'                => Response.new(200, {'return_value' => nil}),
        'analytic_event_data'     => Response.new(200, {'return_value' => nil}),
      }
      reset
    end

    def agent_run_id
      @id_counter += 1
    end

    def reset
      @mock.each_value(&:revert)
      @id_counter = 0
      @agent_data = []
    end

    def default_response
      Response.new(200, {'return_value' => nil})
    end

    def stub(method, return_value, status=200)
      self.mock[method] ||= default_response
      self.mock[method].override(status, {'return_value' => return_value})
    end

    def stub_exception(method, exception, status=200)
      self.mock[method] ||= default_response
      self.mock[method].override(status, {'exception' => exception})
    end

    def call(env)
      req = ::Rack::Request.new(env)
      res = ::Rack::Response.new
      uri = URI.parse(req.url)

      if uri.path =~ /agent_listener\/\d+\/.+\/(\w+)/
        method = $1
        format = json_format?(uri) && RUBY_VERSION >= '1.9' ? :json : :pruby
        if @mock.keys.include? method
          status, body = @mock[method].evaluate
          res.status = status
          if format == :json
            res.write JSON.dump(body)
          else
            res.write Marshal.dump(body)
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
        @body[1][0][4] = unblob(@body[1][0][4]) if @format == :json
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
