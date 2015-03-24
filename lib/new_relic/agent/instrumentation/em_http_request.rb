# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# Unfortunately, em-http doesn't include version file in `em-http.rb`, so
# manually load version file if EventMachine::HttpRequest is defined.
#
# https://github.com/igrigorik/em-http-request/blob/master/lib/em-http.rb
require 'em-http/version' if defined?(EventMachine::HttpRequest)

module NewRelic::Agent::Instrumentation::EMHttpRequestTracing

  EM_HTTP_MIN_VERSION = NewRelic::VersionNumber.new("1.1.1")

  def self.is_supported_version?
    NewRelic::VersionNumber.new(EventMachine::HttpRequest::VERSION) >= NewRelic::Agent::Instrumentation::EMHttpRequestTracing::EM_HTTP_MIN_VERSION
  end

  def self.trace(client)
    wrapped_request = ::NewRelic::Agent::HTTPClients::EMHTTPRequest.new(client.req)
    t0 = Time.now
    state = NewRelic::Agent::TransactionState.tl_get
    frame = ::NewRelic::Agent::CrossAppTracing.start_trace(state, t0, wrapped_request)

    Proc.new do
      wrapped_response = ::NewRelic::Agent::HTTPClients::EMHTTPResponse.new(client.response_header)
      ::NewRelic::Agent::CrossAppTracing.finish_trace(state, t0, frame, wrapped_request, wrapped_response)
    end
  rescue => e
    NewRelic::Agent.logger.error("Exception during trace setup for EMHttp request", e)
  end

  module HttpConnectionInstr
    attr_accessor :frame_stack

    class Stack
      def initialize
        @store = Array.new
      end

      def pop
        @store.pop
      end

      def push(element)
        @store.push(element)
        self
      end

      def size
        @store.size
      end

      def top
        return nil if size < 1
        @store[size - 1]
      end

      def top?(element)
        return false unless element
        @store[size - 1] == element
      end
    end

    def self.frame_stack
      @frame_stack ||= Stack.new
    end

    def setup_request_with_newrelic(*args)
      client = setup_request_without_newrelic(*args)
      callback = NewRelic::Agent::Instrumentation::EMHttpRequestTracing.trace(client)
      client.newrelic_callback = callback
      HttpConnectionInstr.frame_stack.push(callback)
      client
    end
  end

  module HttpClientInstr

    def self.completed_hash
      @callback_hash ||= {}
    end

    def parse_response_header_with_newrelic(*args)
      parse_response_header_without_newrelic(*args)

      stack = HttpConnectionInstr.frame_stack
      callback = @newrelic_callback
      HttpClientInstr.completed_hash[callback] = callback

      # Newrelic trasaction uses stack and em-http-request uses queue,
      # if there's a single request, no problem, but with em-synchrony,
      # we can use multiple requests(clients) in one connection.
      # We only call callback when the given callback is on top.
      # If not, we can call it later because we already stored the given
      # callback in `@callback_hash`.
      while stack.top?(callback) do
        # If the current request(callback) is not completed yet, stop iterating.
        break unless HttpClientInstr.completed_hash[callback]

        # Delete current request(callback) from the hash and stack.
        HttpClientInstr.completed_hash.delete(callback)
        stack.pop
        callback.call
        callback = stack.top
      end
    end
  end
end

DependencyDetection.defer do
  named :em_http

  depends_on do
    defined?(EventMachine::HttpRequest) && defined?(EventMachine::HttpRequest::VERSION)
  end

  depends_on do
    NewRelic::Agent::Instrumentation::EMHttpRequestTracing.is_supported_version?
  end

  executes do
    ::NewRelic::Agent.logger.info "Installing EMHTTPRequest instrumentation"
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/em_http_request_wrappers'
  end

  executes do
    class EventMachine::HttpConnection
      include NewRelic::Agent::Instrumentation::EMHttpRequestTracing::HttpConnectionInstr

      alias :setup_request_without_newrelic :setup_request
      alias :setup_request :setup_request_with_newrelic
    end

    class EventMachine::HttpClient
      include NewRelic::Agent::Instrumentation::EMHttpRequestTracing::HttpClientInstr

      alias :parse_response_header_without_newrelic :parse_response_header
      alias :parse_response_header :parse_response_header_with_newrelic

      def newrelic_callback=(cb)
        @newrelic_callback = cb
      end
    end
  end
end


