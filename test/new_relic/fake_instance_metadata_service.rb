# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'rack'
require 'rack/request'
require 'fake_server'

module NewRelic
  class FakeInstanceMetadataService < FakeServer
    def initialize(*_)
      super
      reset
    end

    def set_response_for_path(path, response)
      @responses[path] = response
    end

    def response_for_path(path)
      @responses[path]
    end

    def call(env)
      req = ::Rack::Request.new(env)
      path = req.path
      rsp = response_for_path(path)

      case rsp
      when ::Rack::Response
        rsp.to_a
      when String
        [200, {}, [rsp]]
      end
    end

    def reset
      @responses = {}
    end

    def app
      self
    end
  end
end
