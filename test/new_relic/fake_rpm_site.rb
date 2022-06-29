# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'rack'
require 'rack/request'
require 'fake_server'

module NewRelic
  class FakeRpmSite < FakeServer
    def initialize(*_)
      super
      @use_ssl = true
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
