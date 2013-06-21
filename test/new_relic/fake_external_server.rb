# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack'
require 'fake_server'

require 'json' if RUBY_VERSION >= '1.9'

module NewRelic
  class FakeExternalServer < FakeServer

    STATUS_MESSAGE = "<html><head><title>FakeExternalServer status</title></head>" +
      "<body>The FakeExternalServer is rockin'</body></html>"

    def initialize( * )
      super
      @requests = []
    end

    attr_reader :requests

    def call(env)
      @requests << env.dup

      req = ::Rack::Request.new(env)
      res = ::Rack::Response.new
      res.status = req.params["status"].to_i if req.params["status"]

      in_transaction('test') do
        res.write STATUS_MESSAGE
      end
      res.finish
    end

    def reset
      @requests.clear
    end

    def app
      NewRelic::Rack::AgentHooks.new(self)
    end

    def fallback_port
      # Only use fallback port on the FakeCollector....
      nil
    end
  end

  class FakeSecureExternalServer < FakeExternalServer
    def initialize
      super(0, true)
    end
  end
end
