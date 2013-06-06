# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack'
require 'timeout'

require 'json' if RUBY_VERSION >= '1.9'

module NewRelic
  class FakeServer

    def run(port=nil)
      port ||= determine_port
      return if @thread && @thread.alive?
      serve_on_port(port) do
        @thread = Thread.new do
          begin
          ::Rack::Handler::WEBrick.run(app,
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

    @seen_port_failure = false

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
