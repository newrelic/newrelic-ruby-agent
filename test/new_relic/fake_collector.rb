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
    attr_reader :last_socket

    def initialize
      super(DEFAULT_PORT)
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
        'custom_event_data'       => Response.new(200, {'return_value' => nil}),
        'error_event_data'        => Response.new(200, {'return_value' => nil})
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

    def stub_wait(method, wait_time, status=200)
      self.mock[method] ||= default_response
      self.mock[method].override(status, Proc.new { sleep(wait_time); {'return_value' => ""}})
    end

    def call(env)
      @last_socket = Thread.current[:WEBrickSocket]

      req = ::Rack::Request.new(env)
      res = ::Rack::Response.new
      uri = URI.parse(req.url)

      if uri.path =~ /agent_listener\/\d+\/.+\/(\w+)/
        method = $1
        if @mock.keys.include? method
          status, body = @mock[method].evaluate
          res.status = status
          res.write ::NewRelic::JSONWrapper.dump(body)
        else
          res.status = 500
          res.write "Method not found"
        end
        run_id = uri.query =~ /run_id=(\d+)/ ? $1 : nil
        req.body.rewind

        begin
          raw_body = req.body.read
          raw_body = Zlib::Inflate.inflate(raw_body) if req.env["HTTP_CONTENT_ENCODING"] == "deflate"

          body = ::NewRelic::JSONWrapper.load(raw_body)
        rescue
          body = "UNABLE TO DECODE BODY: #{raw_body}"

          # Since this is for testing, output failure at this point. If we
          # don't your only evidence of a problem is in obscure test failures
          # from not receiving the data you expect.
          puts body
        end

        query_params = req.GET

        @agent_data << AgentPost.create(:action       => method,
                                        :body         => body,
                                        :run_id       => run_id,
                                        :format       => :json,
                                        :query_params => query_params)
      end
      res.finish
    end

    def app
      self
    end

    def calls_for(method)
      @agent_data.select { |d| d.action == method.to_s }
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
      attr_accessor :action, :body, :run_id, :format, :query_params
      def initialize(opts={})
        @action       = opts[:action]
        @body         = opts[:body]
        @run_id       = opts[:run_id]
        @format       = opts[:format]
        @query_params = opts[:query_params]
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
        when 'custom_event_data'
          CustomEventDataPost.new(opts)
        when 'error_data'
          ErrorDataPost.new(opts)
        when 'error_event_data'
          ErrorEventDataPost.new(opts)
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

      def utilization
        @body["utilization"]
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

      def traces
        @body[0]
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

        def synthetics_resource_id
          @body[9]
        end

        def agent_attributes
          tree.attributes['agentAttributes']
        end

        def custom_attributes
          tree.attributes['userAttributes']
        end

        def intrinsic_attributes
          tree.attributes['intrinsics']
        end
      end

      class SubmittedTransactionTraceTree
        attr_reader :attributes, :nodes, :node_params

        def initialize(body, format)
          @body = body
          @attributes = body[4]
          @nodes = extract_by_index(body[3], 2)
          @node_params = extract_by_index(body[3], 3)
        end

        def extract_by_index(current, index)
          result = [current[index]]
          if current[4].any?
            current[4].each do |child|
              result << extract_by_index(child, index)
            end
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

    class ReservoirSampledContainerPost < AgentPost
      attr_reader :reservoir_metadata, :events

      def initialize opts={}
        super
        @reservoir_metadata = body[1]
        @events = body[2]
      end
    end

    class AnalyticEventDataPost < ReservoirSampledContainerPost; end
    class CustomEventDataPost < ReservoirSampledContainerPost; end
    class ErrorEventDataPost < ReservoirSampledContainerPost; end

    class ErrorDataPost < AgentPost

      attr_reader :errors

      def initialize(opts={})
        super
        @errors = @body[1].map { |e| SubmittedError.new(e) }
      end
    end

    class SubmittedError

      attr_reader :timestamp, :path, :message, :exception_class_name, :params

      def initialize(error_info)
        @timestamp            = error_info[0]
        @path                 = error_info[1]
        @message              = error_info[2]
        @exception_class_name = error_info[3]
        @params               = error_info[4]
      end

      def agent_attributes
        @params["agentAttributes"]
      end

      def custom_attributes
        @params["userAttributes"]
      end

      def intrinsic_attributes
        @params["intrinsics"]
      end
    end
  end
end
