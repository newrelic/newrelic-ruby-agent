# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "net/http"
require "newrelic_rpm"
require "test/unit"
require "http_client_test_cases"

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class NetHttpTest < Test::Unit::TestCase
  include HttpClientTestCases

  def client_name
    "Net::HTTP"
  end

  def get_response
    Net::HTTP.get uri
  end

  def head_response
    Net::HTTP.start(uri.host, uri.port) {|http|
      http.head(uri.path)
    }
  end

  def post_response
    Net::HTTP.start(uri.host, uri.port) {|http|
      http.post(uri.path, "")
    }
  end

  def body(res)
    # to_s for Net::HTTP::Response will return the body string
    res.to_s
  end
end

