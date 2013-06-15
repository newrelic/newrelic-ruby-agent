# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "excon"
require "newrelic_rpm"
require "test/unit"
require "http_client_test_cases"

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class ExconTest < Test::Unit::TestCase
  include HttpClientTestCases

  def client_name
    "Excon"
  end

  def get_response(url=nil)
    Excon.get(url || default_url)
  end

  def head_response
    Excon.head(default_url)
  end

  def post_response
    Excon.post(default_url, :body => "")
  end

  def request_instance
    excon_req = Excon::Connection.new(:scheme => 'http', :host => 'newrelic.com', :port => '80', :path => '/')
    NewRelic::Agent::HTTPClients::ExconHTTPRequest.new(excon_req)
  end

  def response_instance
    NewRelic::Agent::HTTPClients::ExconHTTPResponse.new(Excon::Response.new)
  end

  def test_still_records_tt_node_when_request_fails
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
