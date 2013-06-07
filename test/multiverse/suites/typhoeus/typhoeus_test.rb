# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "typhoeus"
require "newrelic_rpm"
require "test/unit"
require "http_client_test_cases"

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class TyphoeusTest < Test::Unit::TestCase
  include HttpClientTestCases

  def client_name
    "Typhoeus"
  end

  def get_response
    Typhoeus.get(url)
  end

  def head_response
    Typhoeus.head(url)
  end

  def post_response
    Typhoeus.post(url, :body => "")
  end

  def request_instance
    NewRelic::Agent::TyphoeusHTTPRequest.new(Typhoeus::Request.new("http://newrelic.com"))
  end

  def response_instance
    NewRelic::Agent::TyphoeusHTTPResponse.new(Typhoeus::Response.new)
  end

end

