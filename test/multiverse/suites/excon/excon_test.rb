# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "excon"
require "newrelic_rpm"
require "test/unit"
require "http_client_test_cases"

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class ExconTest < MiniTest::Unit::TestCase
  include HttpClientTestCases

  def client_name
    "Excon"
  end

  def get_response(url=nil)
    Excon.get(url || default_url)
  end

  def get_response_multi(url, n)
    responses = []
    conn = Excon.new(url)
    n.times { responses << conn.get }
    conn.reset
    responses
  end

  def head_response
    Excon.head(default_url)
  end

  def post_response
    Excon.post(default_url, :body => "")
  end

  def request_instance
    NewRelic::Agent::HTTPClients::ExconHTTPRequest.new({:headers => ""})
  end

  def response_instance(headers = {})
    NewRelic::Agent::HTTPClients::ExconHTTPResponse.new(Excon::Response.new(:headers => headers))
  end

  def test_still_records_tt_node_when_request_expects_different_response_code
    in_transaction do
      conn = Excon.new("#{default_url}?status=500")
      begin
        conn.request(:method => :get, :expects => [200])
      rescue Excon::Errors::Error => e
        # meh
      end

      last_segment = find_last_transaction_segment()
      assert_equal("External/localhost/Excon/GET", last_segment.metric_name)
    end
  end
end
