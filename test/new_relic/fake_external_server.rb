# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack'
require 'fake_server'
require 'new_relic/rack/agent_hooks'

require 'json' if RUBY_VERSION >= '1.9'

module NewRelic
  class FakeExternalServer < FakeServer

    STATUS_MESSAGE = "<html><head><title>FakeExternalServer status</title></head>" +
      "<body>The FakeExternalServer is rockin'</body></html>"

    attr_reader :overridden_response_headers

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
      @overridden_response_headers = {}
    end

    def override_response_headers(headers)
      @overridden_response_headers.merge!(headers)
    end

    def app
      inner_app = NewRelic::Rack::AgentHooks.new(self)
      server = self
      Proc.new do |env|
        result = inner_app.call(env)
        result[1].merge!(server.overridden_response_headers)
        result
      end
    end
  end

  class FakeSecureExternalServer < FakeExternalServer
    def initialize
      super(0)
      self.use_ssl = true
    end
  end
end
