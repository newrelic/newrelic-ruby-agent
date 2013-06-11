# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "curb"

require "newrelic_rpm"
require "test/unit"
require "http_client_test_cases"
require 'new_relic/agent/http_clients/curb_wrappers'

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class CurbTest < Test::Unit::TestCase
  include HttpClientTestCases

  def client_name
    "Curb"
  end

  def get_response(url=nil)
    Curl.get( url || default_url )
  end

  def head_response
    Curl.head( default_url )
  end

  def post_response
    Curl.post( default_uri )
  end

  def body(res)
    res.body_str
  end

  def request_instance
    NewRelic::Agent::HTTPClients::CurbRequest.new(nil)
  end

  def response_instance
    NewRelic::Agent::HTTPClients::CurbResponse.new(nil)
  end
end

