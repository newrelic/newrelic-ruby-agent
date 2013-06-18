# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack'
require 'fake_server'

require 'json' if RUBY_VERSION >= '1.9'

module NewRelic
  class FakeExternalServer < FakeServer

    STATUS_MESSAGE = "<html><head><title>FakeExternalServer status</title></head><body>The FakeExternalServer is rockin'</body></html>"

    @@port = nil
    @@requests = []

    def call(env)
      @@requests << env.dup

      req = ::Rack::Request.new(env)
      res = ::Rack::Response.new
      res.status = req.params["status"].to_i if req.params["status"]

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

    # Use an ephemeral port to let the system pick. Close and reopen in our fake
    # server machinery, so there is a brief race possible, but hoping it's better
    # than our current "just-pick-a-port" strategy
    def self.determine_port
      return @port unless @port.nil?

      server = TCPServer.new('127.0.0.1', 0)
      @port = server.addr[1]
    ensure
      server.close unless server.nil?
    end

    def determine_port
      FakeExternalServer.determine_port
    end

    def app
      NewRelic::Rack::AgentHooks.new(self)
    end
  end
end
