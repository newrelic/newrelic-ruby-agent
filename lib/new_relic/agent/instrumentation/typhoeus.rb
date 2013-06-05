# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :typhoeus

  depends_on do
    defined?(Typhoeus)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Typhoeus instrumentation'
    require 'uri'
    require 'new_relic/agent/cross_app_tracing'
  end

  executes do
    Typhoeus.before do |request|
      if NewRelic::Agent.is_execution_traced?
        wrapped_request = ::NewRelic::Agent::TyphoeusHTTPRequest.new(request)
        t0, segment = ::NewRelic::Agent::CrossAppTracing.start_trace(wrapped_request)
        request.on_complete do
          wrapped_response = ::NewRelic::Agent::TyphoeusHTTPResponse.new(request.response)
          ::NewRelic::Agent::CrossAppTracing.finish_trace(t0, segment, wrapped_request, wrapped_response)
        end
      end
    end
  end
end


module NewRelic
  module Agent
    class TyphoeusHTTPResponse
      def initialize(response)
        @response = response
      end

      def [](key)
        @response.headers[key]
      end

      def to_hash
        hash = {}
        @response.headers.each do |(k,v)|
          hash[k] = v
        end
        hash
      end
    end

    class TyphoeusHTTPRequest
      def initialize(request)
        @request = request
        @uri = URI.parse(request.url)
      end

      def type
        "Typhoeus"
      end

      def host
        @uri.host
      end

      def method
        (@request.options[:method] || 'GET').upcase
      end

      def [](key)
        @request[key]
      end

      def []=(key, value)
        @request.options[:headers] ||= {}
        @request.options[:headers][key] = value
      end

      def filtered_uri
        # FIXME: not really filtered, need to refactor filtered_uri_for to work
        # more generically.
        @uri.to_s
      end
    end
  end
end
