# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module FlakyProxy
  class Server
    attr_reader :host, :port

    def initialize(host, port)
      @host = host
      @port = port
    end

    def open_socket
      TCPSocket.new(@host, @port)
    end

    def to_s
      "#{@host}:#{@port}"
    end
  end
end
