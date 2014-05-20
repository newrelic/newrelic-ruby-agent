# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rack'
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
      keys_and_values = URI.decode(env.dup["rack.input"].read).split("&")
      result = {}
      keys_and_values.each do |key_and_value|
        key, value = key_and_value.split("=")
        result[key] = value
      end
      result
    end

    def reset
      @requests.clear
    end

    def app
      self
    end
  end
end
