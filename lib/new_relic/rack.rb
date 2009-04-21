require 'rack/response'
require 'newrelic_rpm'
# Rack application for running a metric listener using generic rack adapter
module NewRelic
  module Rack
    class MetricApp
      def initialize
        NewRelic::Agent.manual_start :app_name => 'EPM Agent'
        @stats_engine = NewRelic::Agent.instance.stats_engine
      end
      def call(env)
        request = ::Rack::Request.new env
        body = StringIO.new
        
        segments = request.url.split("?")[0].split("/")
        segments.shift # scheme
        segments.shift # /
        segments.shift # host
        metric = "Custom/" + segments.join("/")
        
        stats = @stats_engine.get_stats(metric, false)
        data = request['value'] && request['value'].to_f
        stats.record_data_point data if data
        body.puts "<h1>Got request!</h1>"
        body.puts "<p>#{metric}=#{data}</p>"
        body.puts "<dl>"
        body.puts "<dt>ip<dd>#{request.ip}"
        body.puts "<dt>host<dd>#{request.host}"
        body.puts "<dt>path<dd>#{request.url}"
        body.puts "<dt>query<dd>#{request.query_string}"
        body.puts "<dt>params<dd>#{request.params.inspect}"
        body.puts "</dl>"
        body.puts "<p><pre>#{env.to_a.map{|k,v| "#{k} = #{v}" }.join("\n")}"
        response = ::Rack::Response.new body.string
        response.finish
      end
    end
  end
end