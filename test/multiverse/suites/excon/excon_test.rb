# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "excon"
require "newrelic_rpm"
require "http_client_test_cases"

class ExconTest < Minitest::Test
  include HttpClientTestCases

  def client_name
    "Excon"
  end

  def get_response(url=nil, headers=nil)
    Excon.get(url || default_url, :headers => (headers || {}))
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

  def put_response
    Excon.put(default_url, :body => "")
  end

  def delete_response
    Excon.delete(default_url)
  end

  def request_instance
    NewRelic::Agent::HTTPClients::ExconHTTPRequest.new({:headers => ""})
  end

  def response_instance(headers = {})
    NewRelic::Agent::HTTPClients::ExconHTTPResponse.new(Excon::Response.new(:headers => headers))
  end

  def test_still_records_tt_node_when_request_fails_with_idempotent_set
    target_url = "#{default_url}/idempotent_test"

    in_transaction do
      conn = Excon.new("#{target_url}?status=404")
      assert_raises(Excon::Errors::NotFound) do
        conn.get(:expects => 200, :idempotent => true)
      end
    end

    tt = NewRelic::Agent.agent.transaction_sampler.last_sample
    node = tt.root_node.called_nodes.first.called_nodes.first
    assert_equal("External/localhost/Excon/GET", node.metric_name)
    assert_equal(target_url, node.params[:uri])
  end

  def test_still_records_tt_node_when_request_expects_different_response_code
    in_transaction do
      conn = Excon.new("#{default_url}?status=500")
      begin
        conn.request(:method => :get, :expects => [200])
      rescue Excon::Errors::Error
        # meh
      end

      last_node = find_last_transaction_node()
      assert_equal("External/localhost/Excon/GET", last_node.metric_name)
    end
  end
end
