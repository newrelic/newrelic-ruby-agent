# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'curb'

require 'newrelic_rpm'
require 'http_client_test_cases'
require 'new_relic/agent/http_clients/curb_wrappers'

class CurbTest < Minitest::Test

  #
  # Tests
  #

  include HttpClientTestCases


  def test_shouldnt_clobber_existing_header_callback
    headers = []
    Curl::Easy.http_get( default_url ) do |handle|
      handle.on_header do |header|
        headers << header
        header.length
      end
    end

    assert !headers.empty?
  end

  def test_shouldnt_clobber_existing_completion_callback
    completed = false
    Curl::Easy.http_get( default_url ) do |handle|
      handle.on_complete do
        completed = true
      end
    end

    assert completed, "completion block was never run"
  end

  def test_get_works_with_the_shortcut_api
    # Override the mechanism for getting a response and run the test_get test
    # again
    @get_response_proc = Proc.new do |url|
      Curl.get( url || default_url )
    end
    test_get
  ensure
    @get_response_proc = nil
  end

  def test_background_works_with_the_shortcut_api
    # Override the mechanism for getting a response and run test_background again
    @get_response_proc = Proc.new do |url|
      Curl.get( url || default_url )
    end
    test_background
  ensure
    @get_response_proc = nil
  end

  def test_get_via_shortcut_api_preserves_header_str
    rsp = Curl.get( default_url )
    header_str = rsp.header_str

    # Make sure that we got something that looks like a header string
    assert_match(/^HTTP\/1\.1 200 OK\s+$/, header_str)
    assert_match(/^Content-Length: \d+\s+$/, header_str)

    # Make sure there are no lines that appear multiple times, which would
    # happen if we installed callbacks repeatedly on one request.
    header_lines = header_str.split
    assert_equal(header_lines.uniq.size, header_lines.size,
      "Found some header lines appearing multiple times in header_str:\n#{header_str}")
  end

  def test_get_via_multi_preserves_header_str
    header_str = nil

    Curl::Multi.get( [default_url] ) do |easy|
      header_str = easy.header_str
    end

    assert_match(/^HTTP\/1\.1 200 OK\s+$/, header_str)
    assert_match(/^Content-Length: \d+\s+$/, header_str)
  end

  def test_get_doesnt_destroy_ability_to_call_status
    status_code = Curl.get( default_url ).status.to_i
    assert_equal(200, status_code)
  end


  # Curl.head is broken in 0.8.4 (https://github.com/taf2/curb/pull/148), but if
  # it ever gets fixed, then this test should be uncommented.

  # def test_head_works_with_the_shortcut_api
  #   # Override the mechanism for getting a response and run the test_get test
  #   # again
  #   def self.head_response
  #     Curl.head( default_url )
  #   end
  #
  #   test_head
  # end

  def test_doesnt_propagate_errors_in_instrumentation
    NewRelic::Agent::CrossAppTracing.stubs( :start_trace ).
      raises( StandardError, "something bad happened" )

    res = Curl::Easy.http_get( default_url )

    assert_kind_of Curl::Easy, res
  end


  def test_works_with_parallel_fetches
    results = []
    other_url = "http://localhost:#{$fake_server.port}/"

    in_transaction("test") do
      Curl::Multi.get( [default_url,other_url] ) do |easy|
        results << easy.body_str
      end

      results.each do |res|
        assert_match %r/<head>/i, res
      end

      last_node = find_last_transaction_node()
      assert_equal "External/Multiple/Curb::Multi/perform", last_node.metric_name
    end
  end

  def test_block_passed_to_multi_perform_should_be_called
    successes = 0
    num_requests = 2
    perform_block_called = false

    in_transaction("test") do
      multi = Curl::Multi.new

      num_requests.times do |i|
        req = Curl::Easy.new(default_url) do |easy|
          easy.on_success { |curl| successes += 1 }
        end
        multi.add(req)
      end

      multi.perform { perform_block_called = true }

      assert_equal(num_requests, successes)
      assert(perform_block_called, "Block passed to Curl::Multi.perform should have been called")
      last_node = find_last_transaction_node()
      assert_equal "External/Multiple/Curb::Multi/perform", last_node.metric_name
    end
  end

  #
  # Helper functions
  #

  def client_name
    "Curb"
  end

  def get_response(url=nil, headers=nil)
    if @get_response_proc
      @get_response_proc.call(url)
    else
      easy = Curl::Easy.new( url || default_url )
      easy.headers = headers unless headers.nil?
      easy.http_get
      easy
    end
  end

  def head_response
    Curl::Easy.http_head( default_url )
  end

  def post_response
    Curl::Easy.http_post( default_url, '' )
  end

  def put_response
    Curl::Easy.http_put( default_url, '' )
  end

  def delete_response
    Curl::Easy.http_delete( default_url )
  end

  def body(res)
    res.body_str
  end

  def request_instance
    NewRelic::Agent::HTTPClients::CurbRequest.new(Curl::Easy.new)
  end

  def response_instance( headers={} )
    res = NewRelic::Agent::HTTPClients::CurbResponse.new(Curl::Easy.new)
    headers.each do |hdr, val|
      res.append_header_data( "#{hdr}: #{val}")
    end

    return res
  end

end
