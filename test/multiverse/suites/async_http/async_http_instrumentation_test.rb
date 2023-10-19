# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'http_client_test_cases'

class AsyncHttpInstrumentationTest < Minitest::Test
  include HttpClientTestCases

  def client_name
    'Async::HTTP'
  end

  def timeout_error_class
    Async::TimeoutError
  end

  def simulate_error_response
    Async::HTTP::Client.any_instance.stubs(:call).raises(timeout_error_class.new('read timeout reached'))
    get_response
  end

  def get_response(url = nil, headers = nil)
    request_and_wait(:get, url || default_url, headers)
  end

  def request_and_wait(method, url, headers = nil, body = nil)
    resp = nil
    Async do
      internet = Async::HTTP::Internet.new
      resp = internet.send(method, url, headers)
      @read_resp = resp&.read
    ensure
      internet&.close
    end
    resp
  end

  def get_wrapped_response(url)
    NewRelic::Agent::HTTPClients::AsyncHTTPResponse.new(get_response(url))
  end

  def head_response
    request_and_wait(:head, default_url)
  end

  def post_response
    request_and_wait(:post, default_url, nil, '')
  end

  def put_response
    request_and_wait(:put, default_url, nil, '')
  end

  def delete_response
    request_and_wait(:delete, default_url, nil, '')
  end

  def request_instance
    NewRelic::Agent::HTTPClients::AsyncHTTPRequest.new(Async::HTTP::Internet.new, 'GET', default_url, {})
  end

  def response_instance(headers = {})
    resp = get_response(default_url, headers)
    headers.each do |k, v|
      resp.headers[k] = v
    end

    NewRelic::Agent::HTTPClients::AsyncHTTPResponse.new(resp)
  end

  def body(res)
    @read_resp
  end

  def test_noticed_error_at_segment_and_txn_on_error
    # skipping this test
    # Async gem does not allow the errors to escape the async block
    # so the errors will never end up on the transaction, only ever the async http segment
  end

  def test_raw_synthetics_header_is_passed_along_if_present_array
    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction do
        NewRelic::Agent::Tracer.current_transaction.raw_synthetics_header = 'boo'

        get_response(default_url, [%w[itsaheader itsavalue]])

        assert_equal 'boo', server.requests.last['HTTP_X_NEWRELIC_SYNTHETICS']
      end
    end
  end

  def test_raw_synthetics_header_is_passed_along_if_present_hash
    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction do
        NewRelic::Agent::Tracer.current_transaction.raw_synthetics_header = 'boo'

        get_response(default_url, {'itsaheader' => 'itsavalue'})

        assert_equal 'boo', server.requests.last['HTTP_X_NEWRELIC_SYNTHETICS']
      end
    end
  end

  def test_raw_synthetics_header_is_passed_along_if_present_protocol_header_hash
    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction do
        NewRelic::Agent::Tracer.current_transaction.raw_synthetics_header = 'boo'

        get_response(default_url, ::Protocol::HTTP::Headers[{'itsaheader' => 'itsavalue'}])

        assert_equal 'boo', server.requests.last['HTTP_X_NEWRELIC_SYNTHETICS']
      end
    end
  end

  def test_raw_synthetics_header_is_passed_along_if_present_protocol_header_array
    with_config(:"cross_application_tracer.enabled" => true) do
      in_transaction do
        NewRelic::Agent::Tracer.current_transaction.raw_synthetics_header = 'boo'

        get_response(default_url, ::Protocol::HTTP::Headers[%w[itsaheader itsavalue]])

        assert_equal 'boo', server.requests.last['HTTP_X_NEWRELIC_SYNTHETICS']
      end
    end
  end
end
