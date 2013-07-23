# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'json'
require 'net/http'
require 'uri'

module Performance
  class HakoClient
    BASE_URI = 'http://hako.pdx.vm.datanerd.us'

    def initialize(token)
      @token = token
    end

    def submit(result)
      body = JSON.dump('result' => result.to_h)

      uri = URI(BASE_URI + "/api/results")
      req = Net::HTTP::Post.new(uri.to_s)
      req.body = body
      req.content_type = 'application/json'
      req['Authorization'] = "Token token=\"#{@token}\""

      Net::HTTP.start(uri.host, uri.port) do |conn|
        conn.request(req)
      end
    end
  end
end
