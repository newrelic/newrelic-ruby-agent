# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'json'
require 'httparty'

module Performance
  class HakoClient
    include HTTParty
    base_uri 'http://hako.herokuapp.com'

    def initialize(token)
      @token = token
    end

    def submit(result)
      body = JSON.dump('result' => result)
      headers = {
        "Authorization" => "Token token=\"#{@token}\"",
        "Content-Type"  => "application/json"
      }
      self.class.post('/api/results', :body => body, :headers => headers)
    end
  end
end
