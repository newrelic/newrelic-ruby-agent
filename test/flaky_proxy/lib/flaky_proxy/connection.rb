# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module FlakyProxy
  class Connection
    def initialize(client_socket, server, rules)
      @client_socket = client_socket
      @server_socket = nil
      @server = server
      @rules = rules
    end

    def client_socket
      @client_socket
    end

    def server_socket
      @server_socket ||= @server.open_socket
    end

    def shutdown
      @client_socket.close if @client_socket && !@client_socket.closed?
      @server_socket.close if @server_socket && !@server_socket.closed?
      @shutdown = true
    end

    def service
      loop do
        service_one
        break if @shutdown
      end
    end

    def service_one
      request = Request.read_from(client_socket)
      if request.complete?
        rule = @rules.match(request)
        rule.evaluate(request, self)
      else
        shutdown
      end
    end
  end
end
