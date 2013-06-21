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

  #
  # Support for shared test cases
  #

  def client_name
    "Net::HTTP"
  end

  def get_response(url=nil)
    uri = default_uri
    uri = URI.parse(url) unless url.nil?

    Net::HTTP.get uri
  end

  def get_response_multi(url, n)
    uri = URI(url)
    responses = []

    Net::HTTP.start(uri.host, uri.port) do |conn|
      n.times do
        req = Net::HTTP::Get.new(url)
        responses << conn.request(req).body
      end
    end

    responses
  end

  def head_response
    Net::HTTP.start(default_uri.host, default_uri.port) {|http|
      http.head(default_uri.path)
    }
  end

  def post_response
    Net::HTTP.start(default_uri.host, default_uri.port) {|http|
      http.post(default_uri.path, "")
    }
  end

  def body(res)
    # to_s for Net::HTTP::Response will return the body string
    res.to_s
  end

  def request_instance
    NewRelic::Agent::HTTPClients::NetHTTPRequest.new(nil, nil)
  end

  def response_instance
    Net::HTTPResponse.new(nil, nil, nil)
  end

  #
  # Net::HTTP specific tests
  #
  def test_get__simple
    Net::HTTP.get default_uri

    assert_metrics_recorded([
      'External/all',
      'External/localhost/Net::HTTP/GET',
      'External/allOther',
      'External/localhost/all'
    ])
  end

  # https://newrelic.atlassian.net/browse/RUBY-835
  def test_direct_get_request_doesnt_double_count
    http = Net::HTTP.new(default_uri.host, default_uri.port)
    http.request(Net::HTTP::Get.new(default_uri.request_uri))

    assert_metrics_recorded([
      'External/localhost/Net::HTTP/GET'
    ])
  end
end

