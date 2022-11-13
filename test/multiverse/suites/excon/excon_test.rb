# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require "excon"
require "newrelic_rpm"
require "http_client_test_cases"

class ExconTest < Minitest::Test
  include HttpClientTestCases

  def client_name
    "Excon"
  end

  def new_timeout_error_class
    Excon::Errors::Timeout.new('read timeout reached')
  end

  def timeout_error_class
    Excon::Errors::Timeout
  end

  def simulate_error_response
    Excon::Socket.any_instance.stubs(:read).raises(new_timeout_error_class)
    get_response
  end

  def get_response(url = nil, headers = nil)
    Excon.get(url || default_url, :headers => (headers || {}))
  end

  def get_wrapped_response(url)
    NewRelic::Agent::HTTPClients::ExconHTTPResponse.new(get_response(url))
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
    Excon.post(default_url, body: String.new)
  end

  def put_response
    Excon.put(default_url, body: String.new)
  end

  def delete_response
    Excon.delete(default_url)
  end

  def request_instance
    params = {
      :method => "get",
      :scheme => "http",
      :host => "localhost",
      :port => 80,
      :path => "",
      :headers => {}
    }
    NewRelic::Agent::HTTPClients::ExconHTTPRequest.new(params)
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

    tt = last_transaction_trace
    node = tt.root_node.children.first.children.first

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
    end

    last_node = find_last_transaction_node()

    assert_equal("External/localhost/Excon/GET", last_node.metric_name)
  end
end
