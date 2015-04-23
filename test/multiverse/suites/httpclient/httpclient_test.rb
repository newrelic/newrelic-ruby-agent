# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "httpclient"
require "newrelic_rpm"
require "http_client_test_cases"

class HTTPClientTest < Minitest::Test
  include HttpClientTestCases

  def client_name
    "HTTPClient"
  end

  def get_response(url=nil, headers=nil)
    HTTPClient.get(url || default_url, :header => headers)
  end

  def head_response
    HTTPClient.head(default_url)
  end

  def post_response
    HTTPClient.post(default_url, :body => "")
  end

  def put_response
    HTTPClient.put(default_url, :body => "")
  end

  def delete_response
    HTTPClient.delete(default_url, :body => "")
  end

  def request_instance
    httpclient_req = HTTP::Message.new_request(:get, 'http://newrelic.com')
    NewRelic::Agent::HTTPClients::HTTPClientRequest.new(httpclient_req)
  end

  def response_instance(headers = {})
    httpclient_resp = HTTP::Message.new_response('')
    headers.each do |k, v|
      httpclient_resp.http_header[k] = v
    end
    NewRelic::Agent::HTTPClients::HTTPClientResponse.new(httpclient_resp)
  end

  def test_still_records_tt_node_when_pop_raises_an_exception
    in_transaction do
      test_exception = StandardError.new
      evil_connection = HTTPClient::Connection.new
      evil_connection.instance_variable_set(:@test_exception, test_exception)
      evil_connection.instance_eval do
        def new_push(request)
          @queue.push(@test_exception)
        end

        alias old_push push
        alias push new_push
      end

      HTTPClient::Connection.stubs(:new).returns(evil_connection)

      begin
        get_response(default_url)
      rescue => e
        raise e unless e == test_exception
      end

      last_node = find_last_transaction_node()
      assert_equal("External/localhost/HTTPClient/GET", last_node.metric_name)
    end
  end
end
