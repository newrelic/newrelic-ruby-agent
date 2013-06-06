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
  class FakeExternalServer

    STATUS_MESSAGE = "<html><head><title>FakeExternalServer status</title></head><body>The FakeExternalServer is rockin'</body></html>"

    @@requests = []

    def call(env)
      @@requests << env.dup

      req = ::Rack::Request.new(env)
      res = ::Rack::Response.new

      in_transaction('test') do
        res.write STATUS_MESSAGE
      end
      res.finish
    end

    def reset
      @@requests = []
    end

    def requests
      @@requests
    end

    # We generate a "unique" port for ourselves based off our pid
    # If this logic changes, look for multiverse newrelic.yml files to update
    # with it duplicated (since we can't easily pull this ruby into a yml)
    def self.determine_port
      30_001 + ($$ % 10_000)
    end

    def determine_port
      FakeExternalServer.determine_port
    end

    @seen_port_failure = false

    def run(port=nil)
      port ||= determine_port
      return if @thread && @thread.alive?
      serve_on_port(port) do
        @thread = Thread.new do
          begin
          ::Rack::Handler::WEBrick.run(NewRelic::Rack::AgentHooks.new(self),
                                       :Port => port,
                                       :Logger => ::WEBrick::Log.new("/dev/null"),
                                       :AccessLog => [ ['/dev/null', ::WEBrick::AccessLog::COMMON_LOG_FORMAT] ]
                                      )
          rescue Errno::EADDRINUSE => ex
            msg = "Port #{port} for FakeExternalServer was in use"
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
