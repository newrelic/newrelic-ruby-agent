# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This is a simple TCP server that binds to an ephemeral port, accepts
# incoming connections on that port, and then closes those connections
# immediately thereafter.
#
# Its purpose is to emulate a misbehaving HTTP server (or flaky network
# connection) by closing the TCP connection without sending an HTTP response.

require 'socket'

module NewRelic
  class EvilServer
    attr_reader :port, :requests

    def initialize
      @requests = []
    end

    def should_run?
      @state == :running
    end

    def stop
      @state = :stopped

      # just a lazy way of just forcing the server to wakeup from accept
      TCPSocket.open("localhost", @port).close rescue nil

      @thread.join
      @thread = nil
    end

    def start
      return if @thread && @thread.alive?
      @requests = []
      @server = TCPServer.new(0)
      @port = @server.addr[1]
      @state = :running
      @thread = Thread.new { run }
      @thread.abort_on_exception = true
    end

    def run
      loop do
        client = @server.accept
        @requests << client.readpartial(1024) if should_run?
        client.close
        break unless should_run?
      end
    end
  end
end
