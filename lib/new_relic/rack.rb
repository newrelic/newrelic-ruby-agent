require 'rack/response'
require 'newrelic_rpm'
# Rack application for running a metric listener using generic rack adapter
module NewRelic
  module Rack
    class MetricApp
      def initialize
        NewRelic::Agent.manual_start :app_name => 'EPM Agent'
      end
      def call(env)
        request = ::Rack::Request.new env
        body = StringIO.new
        body.puts "<h1>Got request!</h1>"
        body.puts "<dl>"
        body.puts "<dt>path<dd>#{request.url}"
        body.puts "<dt>query<dd>#{request.query_string}"
        body.puts "<dt>params<dd>#{request.params.inspect}"
        body.puts "</dl>"
        response = ::Rack::Response.new body.string
        response.finish
      end
    end
  end
end