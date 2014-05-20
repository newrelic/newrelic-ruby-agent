# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack'
require 'rack/request'
require 'fake_server'

module NewRelic
  class FakeRpmSite < FakeServer
    def initialize(*_)
      super
      @requests = []
    end

    attr_reader :requests

    def call(env)
      @requests << unpack(env)
      [200, {}, ["Fine"]]
    end

    def unpack(env)
      ::Rack::Request.new(env).params
    end

    def reset
      @requests.clear
    end

    def app
      self
    end
  end
end
